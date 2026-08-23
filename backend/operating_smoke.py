import os
import tempfile
from datetime import date, timedelta
from pathlib import Path

with tempfile.TemporaryDirectory() as directory:
    database_path = Path(directory, "operating.db").as_posix()
    os.environ["APP_ENV"] = "development"
    os.environ["DATABASE_URL"] = f"sqlite:///{database_path}"
    os.environ["APP_PASSWORD"] = "test-password-123"
    os.environ["JWT_SECRET"] = "x" * 40

    from fastapi.testclient import TestClient
    from app.assistant import execute_tool, tools_for_mode
    from app.db import SessionLocal, engine
    from app.main import app
    from app.models import EventLog

    client = TestClient(app)
    assert {tool["function"]["name"] for tool in tools_for_mode("chat")} == {"get_dashboard", "get_daily_focus"}
    assert len(tools_for_mode("plan")) > len(tools_for_mode("chat"))
    login = client.post("/auth/login", json={"password": "test-password-123"})
    assert login.status_code == 200, login.text
    headers = {"Authorization": "Bearer " + login.json()["access_token"]}
    today = date.today()
    account = client.post("/finance/accounts", headers=headers, json={"name": "Operating cash", "balance_cents": 100000})
    assert account.status_code == 200, account.text
    account_id = account.json()["id"]
    income = client.post("/finance/transactions", headers=headers, json={"account_id": account_id, "kind": "income", "amount_cents": 50000, "occurred_on": today.isoformat(), "expected_on": (today + timedelta(days=1)).isoformat(), "status": "planned"})
    expense = client.post("/finance/transactions", headers=headers, json={"account_id": account_id, "kind": "expense", "amount_cents": 20000, "occurred_on": today.isoformat(), "expected_on": (today + timedelta(days=2)).isoformat(), "status": "planned"})
    debt = client.post("/finance/debts", headers=headers, json={"creditor": "Supplier", "principal_cents": 30000, "outstanding_cents": 30000, "due_on": (today + timedelta(days=3)).isoformat()})
    assert income.status_code == expense.status_code == debt.status_code == 200
    cashflow = client.get("/dashboard/cashflow?days=7", headers=headers)
    assert cashflow.status_code == 200, cashflow.text
    balances = [point["balance_cents"] for point in cashflow.json()["points"]]
    assert balances[0] == 100000 and balances[1] == 150000 and balances[2] == 130000 and balances[3] == 100000, balances
    assistant_db = SessionLocal()
    assistant_dashboard = execute_tool("get_dashboard", {}, assistant_db)
    assistant_db.close()
    assert assistant_dashboard["cash_yuan"] == 1000
    assert "cash_cents" not in assistant_dashboard

    project = client.post("/projects", headers=headers, json={"name": "Launch", "objective": "Validate demand", "success_criteria": "Ten interviews", "stage": "discovery"})
    assert project.status_code == 200, project.text
    project_id = project.json()["id"]
    task = client.post("/tasks", headers=headers, json={"project_id": project_id, "title": "Interview first customer", "impact": 5, "urgency": 5, "estimated_minutes": 30})
    assert task.status_code == 200, task.text
    focus = client.get("/daily-focus", headers=headers)
    assert focus.status_code == 200 and focus.json()["focus"][0]["title"] == "Interview first customer", focus.text
    second_task = client.post("/tasks", headers=headers, json={"project_id": project_id, "title": "Prepare interview notes"})
    assert second_task.status_code == 200, second_task.text
    second_task_id = second_task.json()["id"]
    first_task_id = task.json()["id"]
    dependency = client.patch(f"/tasks/{second_task_id}", headers=headers, json={"dependency_ids": [first_task_id]})
    assert dependency.status_code == 200, dependency.text
    cycle = client.patch(f"/tasks/{first_task_id}", headers=headers, json={"dependency_ids": [second_task_id]})
    assert cycle.status_code == 422 and "cycle" in cycle.text, cycle.text
    blocked = client.patch(f"/tasks/{second_task_id}", headers=headers, json={"status": "blocked", "blocked_reason": "Waiting for customer"})
    assert blocked.status_code == 200, blocked.text
    focus_after_block = client.get("/daily-focus", headers=headers)
    assert any(item["id"] == second_task_id for item in focus_after_block.json()["blocked"]), focus_after_block.text

    db = SessionLocal()
    proposal = execute_tool("propose_tasks", {"project_id": project_id, "tasks": [{"title": "Confirm pricing", "impact": 4, "urgency": 4}]}, db)
    assert proposal["status"] == "pending_confirmation"
    db.close()
    action_id = client.get("/assistant/actions?status=pending", headers=headers).json()["items"][0]["id"]
    assert client.post(f"/assistant/actions/{action_id}/confirm", headers=headers).status_code == 200
    plan_db = SessionLocal()
    planned = execute_tool("create_project_plan", {"name": "Pricing", "objective": "Set price", "tasks": [{"title": "Draft offer", "priority": 4}]}, db=plan_db)
    plan_db.close()
    assert planned["status"] == "pending_confirmation"
    project_action_id = client.get("/assistant/actions?status=pending", headers=headers).json()["items"][-1]["id"]
    project_confirmation = client.post(f"/assistant/actions/{project_action_id}/confirm", headers=headers)
    assert project_confirmation.status_code == 200 and project_confirmation.json()["result"]["project_id"]
    finance_db = SessionLocal()
    finance_proposal = execute_tool("propose_finance_entry", {"kind": "income", "amount_cents": 68000, "occurred_on": today.isoformat(), "counterparty": "微信小店"}, db=finance_db)
    finance_db.close()
    assert finance_proposal["status"] == "pending_confirmation"
    finance_action_id = client.get("/assistant/actions?status=pending", headers=headers).json()["items"][-1]["id"]
    finance_confirmation = client.post(f"/assistant/actions/{finance_action_id}/confirm", headers=headers)
    assert finance_confirmation.status_code == 200 and finance_confirmation.json()["result"]["transaction_id"]
    summary_after_finance = client.get("/dashboard/summary", headers=headers)
    assert summary_after_finance.status_code == 200 and summary_after_finance.json()["cash_cents"] == 168000, summary_after_finance.text
    legacy_finance_db = SessionLocal()
    legacy_finance = execute_tool("propose_tasks", {"tasks": [{"description": "登记微信小店收入680元，今天下午"}]}, db=legacy_finance_db)
    legacy_finance_db.close()
    legacy_finance_id = client.get("/assistant/actions?status=pending", headers=headers).json()["items"][-1]["id"]
    legacy_finance_confirmation = client.post(f"/assistant/actions/{legacy_finance_id}/confirm", headers=headers)
    assert legacy_finance_confirmation.status_code == 200 and legacy_finance_confirmation.json()["result"]["legacy_converted"] is True
    legacy_db = SessionLocal()
    legacy_proposal = execute_tool("propose_tasks", {"tasks": [{"description": "兼容旧版本事项草案"}]}, db=legacy_db)
    legacy_db.close()
    legacy_action_id = client.get("/assistant/actions?status=pending", headers=headers).json()["items"][-1]["id"]
    legacy_confirmation = client.post(f"/assistant/actions/{legacy_action_id}/confirm", headers=headers)
    assert legacy_confirmation.status_code == 200 and legacy_confirmation.json()["result"]["count"] == 1
    weekly_db = SessionLocal()
    weekly_proposal = execute_tool("create_weekly_plan", {"week_start": "2026-08-31", "theme": "Focus", "outcomes": ["Ship one thing"], "priorities": ["Build"]}, db=weekly_db)
    weekly_db.close()
    assert weekly_proposal["status"] == "pending_confirmation"
    weekly_action_id = client.get("/assistant/actions?status=pending", headers=headers).json()["items"][-1]["id"]
    weekly_confirmation = client.post(f"/assistant/actions/{weekly_action_id}/confirm", headers=headers)
    assert weekly_confirmation.status_code == 200 and weekly_confirmation.json()["result"]["weekly_plan_id"]

    current_week_start = date.today() - timedelta(days=date.today().weekday())
    weekly = client.post("/weekly-plans", headers=headers, json={"week_start": current_week_start.isoformat(), "theme": "Validate", "outcomes": ["One decision"], "priorities": ["Interview"]})
    assert weekly.status_code == 200, weekly.text
    current = client.get("/weekly-plans/current", headers=headers)
    assert current.status_code == 200 and current.json()["item"]["theme"] == "Validate"
    audit_db = SessionLocal()
    event_types = {item.event_type for item in audit_db.query(EventLog).all()}
    assert {"account.created", "transaction.created", "debt.created", "assistant.action.proposed", "assistant.action.confirmed"}.issubset(event_types), event_types
    audit_db.close()
    engine.dispose()

print("operating smoke ok")
