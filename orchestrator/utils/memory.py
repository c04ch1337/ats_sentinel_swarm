from qdrant_client import QdrantClient
class VectorMemory:
    def __init__(self, url: str):
        self.client = QdrantClient(url=url)
    def ping(self):
        return self.client.get_collections()
