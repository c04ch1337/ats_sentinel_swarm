import os, httpx, base64, json
class JiraConnector:
    def __init__(self):
        self.base = os.getenv("JIRA_BASE_URL","" ).rstrip('/'); self.email=os.getenv("JIRA_EMAIL","" ); self.token=os.getenv("JIRA_API_TOKEN","" )
        self.session = httpx.AsyncClient(timeout=30.0)
    async def create_issue(self, project_key: str, summary: str, description: str, issue_type: str = 'Task', labels: list = None, components: list = None, priority: str = None, custom_fields: dict = None):
        url=f"{self.base}/rest/api/3/issue"; auth=base64.b64encode(f"{self.email}:{self.token}".encode()).decode()
        headers={"Authorization":f"Basic {auth}","Accept":"application/json","Content-Type":"application/json"}
        payload={"fields":{"project":{"key":project_key},"summary":summary,"description":description,"issuetype":{"name":issue_type},**({"labels":labels} if labels else {}),**({"components":[{"name":c} for c in (components or [])]} if components else {}),**({"priority":{"name":priority}} if priority else {}),**(custom_fields or {})}}
        r=await self.session.post(url,headers=headers,content=json.dumps(payload)); 
        try: data=r.json()
        except Exception: data={"status_code":r.status_code,"text":r.text}
        return {"status_code":r.status_code,"data":data}
    async def add_attachment(self, issue_key: str, filepath: str):
        url=f"{self.base}/rest/api/3/issue/{issue_key}/attachments"; headers={"X-Atlassian-Token":"no-check","Accept":"application/json"}
        files={"file":(os.path.basename(filepath), open(filepath,"rb"), "application/octet-stream")}
        r=await self.session.post(url, headers=headers, files=files, auth=(self.email,self.token))
        try: data=r.json()
        except Exception: data={"status_code":r.status_code,"text":r.text}
        return {"status_code":r.status_code,"data":data}
    async def add_comment(self, issue_key: str, comment: str):
        url=f"{self.base}/rest/api/3/issue/{issue_key}/comment"
        r=await self.session.post(url, auth=(self.email,self.token), headers={"Accept":"application/json","Content-Type":"application/json"}, json={"body": comment})
        try: data=r.json()
        except Exception: data={"status_code":r.status_code,"text":r.text}
        return {"status_code":r.status_code,"data":data}
    async def get_issue(self, issue_key: str):
        url=f"{self.base}/rest/api/3/issue/{issue_key}"
        r=await self.session.get(url, auth=(self.email,self.token), headers={"Accept":"application/json"})
        try: data=r.json()
        except Exception: data={"status_code":r.status_code,"text":r.text}
        return {"status_code":r.status_code,"data":data}
