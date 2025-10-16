from typing import Any, List
def _path(parent: list[str], key: Any) -> str:
    esc = str(key).replace("~","~0").replace("/","~1")
    return "/" + "/".join(parent + [esc]) if parent or key != "" else "/"
def _diff(old, new, parent=None, patch=None):
    if parent is None: parent = []
    if patch is None: patch = []
    if type(old) != type(new):
        patch.append({"op":"replace","path":"/" if not parent else "/"+"/".join(parent), "value": new}); return patch
    if isinstance(old, dict):
        for k in old.keys() - new.keys(): patch.append({"op":"remove","path":_path(parent,k)})
        for k in new.keys():
            if k not in old: patch.append({"op":"add","path":_path(parent,k),"value":new[k]})
            else: _diff(old[k], new[k], parent+[k], patch)
    elif isinstance(old, list):
        if old != new: patch.append({"op":"replace","path":"/"+"/".join(parent), "value": new})
    else:
        if old != new: patch.append({"op":"replace","path":"/"+"/".join(parent), "value": new})
    return patch
def make_patch(current, desired) -> List[dict]: return _diff(current, desired)
def summarize_patch(patch: List[dict]) -> list[str]:
    lines=[]; 
    for p in patch:
        op=p.get("op"); path=p.get("path"); lines.append(f"{op.upper()} {path}")
    return lines
