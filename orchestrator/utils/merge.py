from collections import defaultdict

def merge_iocs(results: list[dict]) -> dict:
    merged = defaultdict(set)
    for r in results:
        for k, vals in (r or {}).items():
            for v in vals:
                merged[k].add(v)
    return {k: sorted(list(v)) for k,v in merged.items()}

def top_values(d: dict, n: int = 20) -> dict:
    return {k: (v[:n] if isinstance(v,list) else v) for k,v in (d or {}).items()}
