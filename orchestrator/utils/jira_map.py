import yaml, os
DEFAULT = {"project_key":"SEC","default_issue_type":"Task","default_labels":["BLUE-SWARM","TRIAGE"],"components":["Security"],"priority_map":{"critical":"Highest","high":"High","medium":"Medium","low":"Low"},"custom_fields":{}}
def load_map(path: str = "configs/jira_fieldmap.yml"): 
    if not os.path.exists(path): return DEFAULT
    with open(path,"r") as f: data = yaml.safe_load(f) or {}
    out = DEFAULT.copy()
    out.update({k:v for k,v in data.items() if v is not None})
    if "priority_map" in data: out["priority_map"].update(data["priority_map"] or {})
    if "custom_fields" in data: out["custom_fields"].update(data["custom_fields"] or {})
    return out
def map_priority(sev: str, fmap: dict):
    if not sev: return None
    return fmap.get("priority_map",{}).get(str(sev).lower())
