import os
os.environ["APP_ENV"] = "development"
os.environ["DATABASE_URL"] = "sqlite:///./release-test.db"
os.environ["APP_PASSWORD"] = "test-password-123"
os.environ["JWT_SECRET"] = "x" * 40
from fastapi.testclient import TestClient
from app.main import app
client = TestClient(app)
assert client.get("/health").status_code == 200
assert client.get("/dashboard/summary").status_code == 401
login = client.post("/auth/login", json={"password": "test-password-123"})
assert login.status_code == 200, login.text
headers = {"Authorization": "Bearer " + login.json()["access_token"]}
assert client.get("/dashboard/summary", headers=headers).status_code == 200
assistant = client.post("/assistant/command", headers=headers, json={"text": "show dashboard"})
assert assistant.status_code == 200, assistant.text
print("release smoke ok")
