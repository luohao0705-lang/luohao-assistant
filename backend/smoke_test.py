import os
os.environ["APP_ENV"] = "development"
os.environ["DATABASE_URL"] = "sqlite:///./release-test.db"
os.environ["APP_PASSWORD"] = "86"
os.environ["JWT_SECRET"] = "x" * 40
from fastapi.testclient import TestClient
from app.main import app
client = TestClient(app)
assert client.get("/health").status_code == 200
assert app.version == "0.4.0"
assert client.get("/dashboard/summary").status_code == 401
login = client.post("/auth/login", json={"password": "86"})
assert login.status_code == 200, login.text
headers = {"Authorization": "Bearer " + login.json()["access_token"]}
assert client.get("/dashboard/summary", headers=headers).status_code == 200
assert client.get("/finance/accounts", headers=headers).status_code == 200
assert client.get("/finance/transactions", headers=headers).status_code == 200
assert client.get("/finance/debts", headers=headers).status_code == 200
account = client.post("/finance/accounts", headers=headers, json={"name": "测试账户", "kind": "bank", "balance_cents": 120000, "currency": "CNY"})
assert account.status_code == 200, account.text
transaction = client.post("/finance/transactions", headers=headers, json={"account_id": account.json()["id"], "kind": "expense", "amount_cents": 1999, "occurred_on": "2026-08-24", "status": "confirmed", "counterparty": "测试支出"})
assert transaction.status_code == 200, transaction.text
assert client.patch(f"/finance/transactions/{transaction.json()['id']}", headers=headers, json={"status": "paid"}).status_code == 200
debt = client.post("/finance/debts", headers=headers, json={"creditor": "测试债权人", "principal_cents": 50000, "outstanding_cents": 50000, "due_on": "2026-09-30"})
assert debt.status_code == 200, debt.text
assert client.patch(f"/finance/debts/{debt.json()['id']}", headers=headers, json={"outstanding_cents": 45000}).status_code == 200
assistant = client.post("/assistant/command", headers=headers, json={"text": "show dashboard"})
assert assistant.status_code == 200, assistant.text
print("release smoke ok")
