from fastapi import FastAPI, Body, UploadFile, File, Form
from fastapi.responses import PlainTextResponse
from fastapi.staticfiles import StaticFiles
from loguru import logger
from typing import List, Optional
import os, yaml, shutil, time, json

from orchestrator.providers.llm_provider import get_llm_provider
from orchestrator.utils.memory import VectorMemory
from orchestrator.connectors.jira import JiraConnector
from orchestrator.connectors.zpa import ZPAConnector
from orchestrator.connectors.rapid7_idr import IDRConnector
from orchestrator.utils.jira_map import load_map, map_priority
from orchestrator.utils.markdown import build_description
from orchestrator.utils.ingest import analyze_path
from orchestrator.utils.jsonpatcher import make_patch, summarize_patch
from orchestrator.utils.merge import merge_iocs, top_values

from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

REQUESTS = Counter('blue_swarm_requests_total', 'Total HTTP requests', ['path', 'method'])
LATENCY = Histogram('blue_swarm_request_latency_seconds', 'Request latency', ['path', 'method'])
FILES_ANALYZED = Counter('blue_swarm_files_analyzed_total', 'Total files analyzed')
IOCS_FOUND = Counter('blue_swarm_iocs_found_total', 'Total IOCs found')
JIRA_ISSUES = Counter('blue_swarm_jira_issues_created_total', 'Total JIRA issues created')
JIRA_ATTS = Counter('blue_swarm_jira_attachments_uploaded_total', 'Total JIRA attachments uploaded')
ZPA_DIFFS = Counter('blue_swarm_zpa_diffs_total', 'Total ZPA diffs rendered')
ZPA_ENFORCE_ATTEMPTS = Counter('blue_swarm_zpa_enforce_attempts_total', 'Total ZPA enforce attempts')
ZPA_ENFORCE_APPLIED = Counter('blue_swarm_zpa_enforce_applied_total', 'Total ZPA enforce applied')
ZPA_ENFORCE_BLOCKED = Counter('blue_swarm_zpa_enforce_blocked_total', 'Total ZPA enforce blocked')
ENRICH_ATTEMPTS = Counter('blue_swarm_enrich_attempts_total', 'Unified enrich attempts')
ENRICH_COMMENTS = Counter('blue_swarm_enrich_comments_total', 'Unified enrich comments posted')

def instrument(path: str, method: str):
    def deco(fn):
        async def wrapped(*args, **kwargs):
            REQUESTS.labels(path=path, method=method).inc()
            start = time.time()
            try:
                return await fn(*args, **kwargs)
            finally:
                LATENCY.labels(path=path, method=method).observe(time.time() - start)
        return wrapped
    return deco

app = FastAPI(title="Blue Team Co-Pilot Orchestrator", version="1.5")
app.mount('/', StaticFiles(directory='static', html=True), name='static')

memory = VectorMemory(os.getenv("QDRANT_URL", "http://localhost:6333"))
llm = get_llm_provider()

jira = JiraConnector()
zpa = ZPAConnector()
idr = IDRConnector()

@app.get("/healthz")
async def health(): return {"status":"ok"}

@app.get("/metrics")
async def metrics():
    data = generate_latest()
    return PlainTextResponse(data.decode('utf-8'), media_type=CONTENT_TYPE_LATEST)

@app.get("/agents")
async def list_agents():
    with open("agents/blue_team_roster.yaml","r") as f: roster = yaml.safe_load(f)
    return roster

@app.post("/upload")
@instrument("/upload","POST")
async def upload(agent_id: str = Form(...), create_jira: Optional[bool] = Form(False), files: List[UploadFile] = File(...)):
    saved = []; os.makedirs("uploads", exist_ok=True)
    for uf in files:
        dest = os.path.join("uploads", uf.filename)
        with open(dest, "wb") as out: shutil.copyfileobj(uf.file, out)
        saved.append(dest)
    logger.info(f"[UPLOAD] agent={agent_id} saved={saved} jira?={create_jira}")
    return {"agent_id": agent_id, "saved": saved, "jira_requested": create_jira}

@app.post("/tasks/run")
@instrument("/tasks/run","POST")
async def run_task(agent_id: str = Body(...), input: dict = Body(default={})):
    logger.info(f"Agent {agent_id} running with keys={list(input.keys())}")
    return {"agent_id": agent_id, "received": input, "note": "stub - route to agent pipeline"}

@app.post("/ingest/analyze")
@instrument("/ingest/analyze","POST")
async def ingest_analyze(paths: list[str] = Body(..., embed=True)):
    results = []; total_iocs = 0
    for p in paths:
        res = analyze_path(p); results.append(res)
        if res.get("exists"):
            FILES_ANALYZED.inc()
            total_iocs += sum(len(v) for v in res.get("iocs", {}).values())
    if total_iocs: IOCS_FOUND.inc(total_iocs)
    return {"results": results, "iocs_total": total_iocs}

@app.get("/idr/notables")
@instrument("/idr/notables","GET")
async def idr_notables(start_time: str = None, end_time: str = None, limit: int = 100):
    return await idr.get_notables(start_time=start_time, end_time=end_time, limit=limit)

def _normalize_notable(n: dict):
    title = n.get('title') or n.get('name') or 'IDR Notable'
    severity = (n.get('severity') or n.get('risk') or 'medium').lower()
    desc = n.get('description') or n.get('summary') or ''
    iocs = {}
    for key in ['indicators','iocs','entities','observables']:
        val = n.get(key)
        if isinstance(val, dict):
            for k, v in val.items():
                if isinstance(v, list) and v: iocs.setdefault(k, []).extend([str(x) for x in v if x])
        elif isinstance(val, list):
            for item in val:
                if isinstance(item, dict):
                    typ = item.get('type') or item.get('kind') or 'value'
                    val = item.get('value') or item.get('indicator') or item.get('name')
                    if val: iocs.setdefault(typ, []).append(str(val))
    assets = []
    for key in ['assets','hosts','targets']:
        val = n.get(key)
        if isinstance(val, list): assets += [str(x) for x in val]
        elif isinstance(val, dict): assets += [str(v) for v in val.values()]
    return dict(title=title, severity=severity, description=desc, iocs={k:list(set(v)) for k,v in iocs.items()}, assets=list(set(assets)))

@app.post("/idr/notables/pull")
@instrument("/idr/notables/pull","POST")
async def idr_notables_pull(since: str = Body(None), until: str = Body(None), limit: int = Body(50), create_jira: bool = Body(False), project_key: str = Body(None), notes: str = Body("")):
    raw = await idr.get_notables(start_time=since, end_time=until, limit=limit)
    data = raw.get("data") if isinstance(raw, dict) else raw
    items = []
    candidates = data["data"] if isinstance(data, dict) and isinstance(data.get("data"), list) else (data if isinstance(data, list) else [])
    fmap = load_map()
    for n in candidates:
        norm = _normalize_notable(n)
        desc = build_description(norm["title"], norm["description"], norm["iocs"], assets=norm["assets"], notes=notes)
        items.append(dict(summary=norm["title"], severity=norm["severity"], description=desc, iocs=norm["iocs"], assets=norm["assets"]))
    created = []
    if create_jira and os.getenv("JIRA_ENABLE_WRITE","false").lower() == "true":
        pj = project_key or fmap["project_key"]
        for it in items:
            priority = map_priority(it["severity"], fmap)
            issue = await jira.create_issue(project_key=pj, summary=it["summary"], description=it["description"], issue_type=fmap.get("default_issue_type","Task"), labels=fmap.get("default_labels",[]), components=fmap.get("components",[]), priority=priority, custom_fields=fmap.get("custom_fields",{}))
            created.append(issue)
            if issue.get("status_code",0) < 300: JIRA_ISSUES.inc()
    return {"items": items, "created": created, "raw": raw}

@app.get("/zpa/app_segments")
@instrument("/zpa/app_segments","GET")
async def zpa_app_segments(limit: int = 200):
    return await zpa.list_app_segments(limit=limit)

@app.post("/zpa/diff")
@instrument("/zpa/diff","POST")
async def zpa_diff(desired: dict = Body(...), current: dict = Body(None), fetch_current: bool = Body(False)):
    if current is None and fetch_current:
        cur = await zpa.get_current_policies(); current = cur.get("data", cur)
    current = current or {}
    patch = make_patch(current, desired); summary = summarize_patch(patch); ZPA_DIFFS.inc()
    return {"patch": patch, "summary": summary, "changes": len(patch)}

@app.post("/zpa/enforce")
@instrument("/zpa/enforce","POST")
async def zpa_enforce(patch: list[dict] = Body(...), jira_issue_key: str = Body(...), allow_statuses: list[str] = Body(default=["Approved","Ready for Change"])):
    ZPA_ENFORCE_ATTEMPTS.inc()
    if os.getenv("ZPA_ENABLE_ENFORCE","false").lower() != "true":
        ZPA_ENFORCE_BLOCKED.inc(); return {"status":"blocked","reason":"ZPA enforcement disabled (set ZPA_ENABLE_ENFORCE=true)"}
    ji = await jira.get_issue(jira_issue_key)
    status_name = ji.get("data",{}).get("fields",{}).get("status",{}).get("name","")
    if status_name not in allow_statuses:
        ZPA_ENFORCE_BLOCKED.inc(); return {"status":"blocked","reason":f"JIRA status '{status_name}' not in allowlist {allow_statuses}"}
    ZPA_ENFORCE_APPLIED.inc()
    return {"status":"accepted","applied_ops": len(patch), "note":"Map patch ops to ZPA API calls in your tenant"}

@app.post("/enrich/unified_comment")
@instrument("/enrich/unified_comment","POST")
async def enrich_unified_comment(paths: list[str] = Body(..., embed=True), jira_issue_key: str = Body(None), create_comment: bool = Body(False), include_idr: bool = Body(True), include_zpa: bool = Body(True), notes: str = Body("")):
    ENRICH_ATTEMPTS.inc()
    analyses = [analyze_path(p) for p in paths]
    ioc_sets = [a.get("iocs", {}) for a in analyses if a.get("exists")]
    merged = merge_iocs(ioc_sets); merged_top = top_values(merged, 30)
    zpa_scope = []
    if include_zpa:
        try:
            segs = await zpa.list_app_segments(limit=500)
            doms = set(merged_top.get("domain", [])); urls = set(merged_top.get("url", []))
            hay = json.dumps(segs.get("data", segs))[:500000]; hits=set()
            for d in list(doms)[:50]:
                if d and d in hay: hits.add(d)
            for u in list(urls)[:50]:
                if u and u in hay: hits.add(u)
            zpa_scope = sorted(list(hits))[:50]
        except Exception as e:
            zpa_scope = [f"[ZPA lookup error: {e}]"]
    idr_notes = "IDR context lookup not configured"
    if include_idr and os.getenv("R7_IDR_NOTABLES_PATH"):
        try:
            _ = await idr.get_notables(limit=5); idr_notes = f"IDR reachable via path={os.getenv('R7_IDR_NOTABLES_PATH')}."
        except Exception as e:
            idr_notes = f"[IDR lookup error: {e}]"
    title = "Unified Enrichment Summary"; summary = f"Paths: {', '.join(paths)}"
    comment = build_description(title, summary, merged_top, assets=[], notes=notes)
    if zpa_scope: comment += "\n\n**ZPA scope hints**\n" + "\n".join(f"- {z}" for z in zpa_scope)
    if idr_notes: comment += f"\n\n**IDR notes**\n- {idr_notes}"
    posted=None
    if create_comment and jira_issue_key and os.getenv("JIRA_ENABLE_WRITE","false").lower() == "true":
        res = await jira.add_comment(jira_issue_key, comment); posted=res
        if res.get("status_code",0) < 300: ENRICH_COMMENTS.inc()
    return {"iocs": merged_top, "zpa_scope": zpa_scope, "comment": comment, "jira_posted": posted}
