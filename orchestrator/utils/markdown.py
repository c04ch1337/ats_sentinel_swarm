def ioc_table(iocs: dict) -> str:
    if not iocs: return "_No indicators extracted._"
    rows = ["| Type | Value |","|---|---|"]
    for k, vals in iocs.items():
        for v in sorted(set(vals))[:200]:
            rows.append(f"| {k} | {v} |")
    return "\n".join(rows)
def build_description(title: str, summary: str, iocs: dict, assets: list = None, notes: str = "") -> str:
    lines = []; 
    if summary: lines += [summary.strip(),""]
    if assets: lines += ["**Assets**","\n".join(f"- {a}" for a in assets), ""]
    lines += ["**Indicators**", ioc_table(iocs), ""]
    if notes: lines += ["**Notes**", notes.strip(), ""]
    return "\n".join(lines)
