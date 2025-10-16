import hashlib, mimetypes, re, os
IOC_PATTERNS = {
    "ipv4": re.compile(r"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b"),
    "email": re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
    "url": re.compile(r"\bhttps?://[\w\-\.]+(?:\:[0-9]+)?(?:/[\w\-\./#%?=&+]*)?"),
    "domain": re.compile(r"\b(?!\d+\b)(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}\b"),
    "sha256": re.compile(r"\b[A-Fa-f0-9]{64}\b"),
    "sha1": re.compile(r"\b[A-Fa-f0-9]{40}\b"),
    "md5": re.compile(r"\b[A-Fa-f0-9]{32}\b"),
}
def _hashes(data: bytes):
    import hashlib
    return {"md5": hashlib.md5(data).hexdigest(), "sha1": hashlib.sha1(data).hexdigest(), "sha256": hashlib.sha256(data).hexdigest()}
def analyze_path(path: str):
    out = {"path": path, "exists": False}
    if not os.path.exists(path): return out
    out["exists"] = True
    out["size"] = os.path.getsize(path)
    mime, _ = mimetypes.guess_type(path); out["mime_guess"] = mime or "application/octet-stream"
    with open(path,"rb") as f: data = f.read()
    out["hash"] = _hashes(data)
    text = data.decode("utf-8", errors="ignore"); iocs = {}
    for k, pat in IOC_PATTERNS.items():
        found = list(set(pat.findall(text))); 
        if found: iocs[k] = found[:500]
    out["iocs"] = iocs; return out
