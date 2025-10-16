import os
def get_llm_provider():
    p = os.getenv("LLM_PROVIDER","OPENAI").upper()
    if p=="OPENAI": return {"provider":"openai","model":os.getenv("OPENAI_MODEL","gpt-4o-mini")}
    if p=="ANTHROPIC": return {"provider":"anthropic","model":os.getenv("ANTHROPIC_MODEL","claude-3-5-sonnet")}
    if p=="AZURE_OPENAI": return {"provider":"azure_openai","deployment":os.getenv("AZURE_OPENAI_DEPLOYMENT","")}
    if p=="OLLAMA": return {"provider":"ollama","base_url":os.getenv("OLLAMA_BASE_URL","http://localhost:11434")}
    return {"provider":"none"}
