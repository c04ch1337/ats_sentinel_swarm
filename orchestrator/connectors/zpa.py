import os, httpx
class ZPAConnector:
    def __init__(self):
        self.base=os.getenv("ZPA_BASE_URL","" ).rstrip('/'); self.client_id=os.getenv("ZPA_CLIENT_ID","" ); self.client_secret=os.getenv("ZPA_CLIENT_SECRET","" )
        self.session=httpx.AsyncClient(timeout=30.0)
    async def get(self, path: str, params=None):
        headers={"Authorization": f"Bearer {self.client_secret}"} if self.client_secret else {}
        url=f"{self.base}/{path.lstrip('/')}"; r=await self.session.get(url, headers=headers, params=params or {})
        return {"status_code":r.status_code, "data": r.json() if r.headers.get("content-type","" ).startswith("application/json") else r.text}
    async def post(self, path: str, payload: dict):
        headers={"Authorization": f"Bearer {self.client_secret}", "Content-Type":"application/json"} if self.client_secret else {"Content-Type":"application/json"}
        url=f"{self.base}/{path.lstrip('/')}"; r=await self.session.post(url, headers=headers, json=payload)
        return {"status_code":r.status_code, "data": r.json() if r.headers.get("content-type","" ).startswith("application/json") else r.text}
    async def list_app_segments(self, limit: int = 200, path_env: str = "ZPA_APP_SEGMENTS_PATH"):
        path=os.getenv(path_env,"mgmtconfig/v2/admin/applications"); return await self.get(path, params={"limit":limit})
    async def get_current_policies(self, path_env: str = "ZPA_POLICIES_PATH"):
        path=os.getenv(path_env, "mgmtconfig/v2/admin/applications"); return await self.get(path)
