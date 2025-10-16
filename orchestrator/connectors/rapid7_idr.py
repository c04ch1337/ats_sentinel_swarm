import os, httpx, json
class IDRConnector:
    def __init__(self):
        self.base=os.getenv("R7_IDR_BASE","" ).rstrip('/'); self.api_key=os.getenv("R7_IDR_API_KEY","" )
        self.session=httpx.AsyncClient(timeout=30.0)
    async def get(self, path: str, params=None):
        headers={"X-Api-Key": self.api_key, "Accept":"application/json"}; url=f"{self.base}/{path.lstrip('/')}"
        r=await self.session.get(url, headers=headers, params=params or {})
        return {"status_code": r.status_code, "data": r.json() if r.headers.get("content-type","" ).startswith("application/json") else r.text}
    async def post(self, path: str, payload: dict):
        headers={"X-Api-Key": self.api_key, "Accept":"application/json","Content-Type":"application/json"}; url=f"{self.base}/{path.lstrip('/')}"
        r=await self.session.post(url, headers=headers, content=json.dumps(payload))
        return {"status_code": r.status_code, "data": r.json() if r.headers.get("content-type","" ).startswith("application/json") else r.text}
    async def get_notables(self, start_time: str = None, end_time: str = None, limit: int = 100, path_env: str = "R7_IDR_NOTABLES_PATH"):
        path=os.getenv(path_env, "idr/v1/notables"); params={}
        if start_time: params["start_time"]=start_time
        if end_time: params["end_time"]=end_time
        if limit: params["limit"]=limit
        return await self.get(path, params=params)
