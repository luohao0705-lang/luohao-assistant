import json
import re
from datetime import date, timedelta

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import get_settings
from .models import Account, AssistantAction, Debt, EventLog, Memory, Project, Task, Transaction, WeeklyPlan

TOOLS = [
    {"type": "function", "function": {"name": "propose_tasks", "description": "Propose tasks; owner confirmation is required.", "parameters": {"type": "object", "properties": {"project_id": {"type": ["integer", "null"]}, "tasks": {"type": "array", "items": {"type": "object"}}}, "required": ["tasks"]}}},
    {"type": "function", "function": {"name": "create_project_plan", "description": "Propose a project plan; owner confirmation is required.", "parameters": {"type": "object", "properties": {"name": {"type": "string"}, "objective": {"type": "string"}, "success_criteria": {"type": ["string", "null"]}, "key_hypothesis": {"type": ["string", "null"]}, "risk_summary": {"type": ["string", "null"]}, "next_action": {"type": ["string", "null"]}, "priority": {"type": "integer"}, "due_on": {"type": ["string", "null"]}, "tasks": {"type": "array", "items": {"type": "object"}}}, "required": ["name"]}}},
    {"type": "function", "function": {"name": "create_weekly_plan", "description": "Propose a weekly plan; owner confirmation is required.", "parameters": {"type": "object", "properties": {"week_start": {"type": "string"}, "theme": {"type": ["string", "null"]}, "outcomes": {"type": "array", "items": {"type": "string"}}, "priorities": {"type": "array", "items": {"type": "string"}}, "risks": {"type": "array", "items": {"type": "string"}}}, "required": ["week_start", "outcomes", "priorities"]}}},
    {"type": "function", "function": {"name": "get_daily_focus", "description": "Read today's prioritized command center.", "parameters": {"type": "object", "properties": {}}}},
    {"type": "function", "function": {"name": "get_dashboard", "description": "Read the current operating dashboard.", "parameters": {"type": "object", "properties": {}}}},
]


def _date(value: str | None) -> date | None:
    return date.fromisoformat(value) if value else None


def cashflow_forecast(db: Session, days: int = 90) -> list[dict]:
    accounts = db.scalars(select(Account)).all()
    transactions = db.scalars(select(Transaction)).all()
    debts = db.scalars(select(Debt).where(Debt.status == "open")).all()
    balance = sum(item.balance_cents for item in accounts)
    today = date.today()
    points: list[dict] = []
    for offset in range(days + 1):
        current = today + timedelta(days=offset)
        for item in transactions:
            event_date = item.expected_on or item.occurred_on
            if event_date == current and item.status == "planned":
                balance += item.amount_cents if item.kind == "income" else -item.amount_cents
        for debt in debts:
            if debt.due_on == current:
                balance -= debt.outstanding_cents
        points.append({"date": current.isoformat(), "balance_cents": balance})
    return points


def task_priority_score(item: Task, today: date | None = None) -> int:
    today = today or date.today()
    due_bonus = 0
    if item.due_on:
        days = (item.due_on - today).days
        due_bonus = 3 if days < 0 else 2 if days <= 1 else 1 if days <= 7 else 0
    blocker_penalty = -3 if item.status == "blocked" else 0
    return item.priority * 4 + item.impact * 3 + item.urgency * 2 + due_bonus + blocker_penalty


def daily_focus_snapshot(db: Session) -> dict:
    today = date.today()
    open_tasks = db.scalars(select(Task).where(Task.status.in_(["todo", "in_progress", "blocked"]))).all()
    ranked = sorted(open_tasks, key=lambda item: (-task_priority_score(item, today), item.due_on or date.max, item.id))
    focus = [
        {"id": item.id, "title": item.title, "project_id": item.project_id, "status": item.status, "priority": item.priority, "impact": item.impact, "urgency": item.urgency, "due_on": item.due_on.isoformat() if item.due_on else None, "estimated_minutes": item.estimated_minutes, "score": task_priority_score(item, today)}
        for item in ranked[:3]
    ]
    blocked = [{"id": item.id, "title": item.title, "reason": item.blocked_reason or item.waiting_on or "需要补充说明", "project_id": item.project_id} for item in ranked if item.status == "blocked"]
    overdue = [item for item in open_tasks if item.due_on and item.due_on < today]
    return {"date": today.isoformat(), "focus": focus, "blocked": blocked[:8], "overdue_count": len(overdue), "open_count": len(open_tasks)}


def dashboard_snapshot(db: Session) -> dict:
    accounts = db.scalars(select(Account)).all()
    debts = db.scalars(select(Debt).where(Debt.status == "open")).all()
    transactions = db.scalars(select(Transaction)).all()
    projects = db.scalars(select(Project).where(Project.status.in_(["planning", "active", "paused"]))).all()
    tasks = db.scalars(select(Task).where(Task.status.in_(["todo", "in_progress", "blocked"]))).all()
    today = date.today()
    cash_cents = sum(item.balance_cents for item in accounts)
    outstanding_debt_cents = sum(item.outstanding_cents for item in debts)
    planned_income = sum(item.amount_cents for item in transactions if item.kind == "income" and item.status == "planned" and (item.expected_on or item.occurred_on) >= today)
    planned_expense = sum(item.amount_cents for item in transactions if item.kind == "expense" and item.status == "planned" and (item.expected_on or item.occurred_on) >= today)
    due_soon = sum(item.outstanding_cents for item in debts if item.due_on and 0 <= (item.due_on - today).days <= 30)
    overdue_income = sum(item.amount_cents for item in transactions if item.kind == "income" and item.status == "planned" and (item.expected_on or item.occurred_on) < today)
    forecast = cashflow_forecast(db, 90)
    lowest = min(forecast, key=lambda item: item["balance_cents"]) if forecast else {"date": today.isoformat(), "balance_cents": cash_cents}
    risk_flags = []
    if lowest["balance_cents"] < 0:
        risk_flags.append(f"预计 {lowest['date']} 出现现金缺口：{abs(lowest['balance_cents'])} 分")
    if due_soon > cash_cents:
        risk_flags.append("未来 30 天到期债务超过当前现金")
    if overdue_income:
        risk_flags.append(f"逾期预计收入：{overdue_income} 分")
    blocked_count = sum(1 for item in tasks if item.status == "blocked")
    if blocked_count:
        risk_flags.append(f"有待你处理的阻塞事项：{blocked_count} 项")
    return {"cash_cents": cash_cents, "outstanding_debt_cents": outstanding_debt_cents, "planned_income_cents": planned_income, "planned_expense_cents": planned_expense, "debt_due_30d_cents": due_soon, "overdue_income_cents": overdue_income, "forecast_lowest_balance_cents": lowest["balance_cents"], "forecast_lowest_date": lowest["date"], "active_projects": len(projects), "open_tasks": len(tasks), "blocked_tasks": blocked_count, "risk_flags": risk_flags}


def _pending_action(action_type: str, arguments: dict, db: Session) -> dict:
    action = AssistantAction(action_type=action_type, payload_json=json.dumps(arguments, ensure_ascii=False), status="pending")
    db.add(action)
    db.add(EventLog(event_type="assistant.action.proposed", payload_json=json.dumps({"action_type": action_type, "payload": arguments}, ensure_ascii=False)))
    db.commit()
    db.refresh(action)
    return {"pending_action_id": action.id, "status": "pending_confirmation", "action_type": action_type}


def execute_tool(name: str, arguments: dict, db: Session) -> dict:
    if name == "get_dashboard":
        return dashboard_snapshot(db)
    if name == "get_daily_focus":
        return daily_focus_snapshot(db)
    if name in {"propose_tasks", "create_project_plan", "create_weekly_plan"}:
        return _pending_action(name, arguments, db)
    return {"error": f"unsupported tool: {name}"}


async def run_assistant(text: str, mode: str, db: Session, history: list[dict] | None = None) -> dict:
    settings = get_settings()
    snapshot = dashboard_snapshot(db)
    daily_focus = daily_focus_snapshot(db)
    terms = [term for term in text.split() if len(term) > 1][:5]
    memory_query = select(Memory).where(Memory.memory_type != "archived").order_by(Memory.id.desc()).limit(10)
    if terms:
        from sqlalchemy import or_
        memory_query = select(Memory).where(Memory.memory_type != "archived", or_(*(Memory.content.ilike(f"%{term}%") for term in terms))).order_by(Memory.id.desc()).limit(10)
    memory_context = [item.content for item in db.scalars(memory_query).all()]
    if not settings.deepseek_api_key:
        return {"reply": "DeepSeek 尚未配置，经营总览和今日重点仍可正常使用。", "snapshot": snapshot, "tool_results": [], "suggestions": []}
    messages = [
        {"role": "system", "content": "你是创业者的经营助理。只使用提供的数据，先给出最重要的判断，明确假设和阻塞点。所有写入必须先生成待确认方案，未经确认不能声称已经写入。用户要求拆解事项、创建项目方案或准备周计划时，使用对应规划工具。请始终使用简洁、自然的中文回答。当你需要用户选择或补充信息时，在回复最后单独一行输出 QUICK_OPTIONS: 选项1 | 选项2 | 选项3，最多 4 个选项；没有选择必要时不要输出这一行。"},
        {"role": "system", "content": json.dumps({"dashboard": snapshot, "daily_focus": daily_focus, "memories": memory_context}, ensure_ascii=False)},
    ]
    # The API is stateless, so the iOS client sends a bounded recent transcript.
    # Keep only valid roles and cap characters to prevent a long chat from crowding out financial context.
    history_messages: list[dict] = []
    history_chars = 0
    for item in reversed(history or []):
        role = item.get("role")
        content = str(item.get("content") or "").strip()
        if role not in {"user", "assistant"} or not content:
            continue
        if history_chars + len(content) > 12000:
            break
        history_messages.insert(0, {"role": role, "content": content})
        history_chars += len(content)
    messages.extend(history_messages)
    messages.append({"role": "user", "content": text})
    payload = {"model": settings.deepseek_reasoner_model if mode == "plan" else settings.deepseek_chat_model, "messages": messages, "tools": TOOLS, "tool_choice": "auto"}
    tool_results = []
    headers = {"Authorization": f"Bearer {settings.deepseek_api_key}", "Content-Type": "application/json"}
    try:
        async with httpx.AsyncClient(timeout=45) as client:
            response = await client.post(f"{settings.deepseek_base_url.rstrip('/')}/chat/completions", headers=headers, json=payload)
            response.raise_for_status()
            message = response.json()["choices"][0]["message"]
            tool_calls = message.get("tool_calls", [])
            for call in tool_calls:
                args = json.loads(call["function"].get("arguments") or "{}")
                result = execute_tool(call["function"]["name"], args, db)
                tool_results.append({"name": call["function"]["name"], "result": result})
                messages.append({"role": "assistant", "content": message.get("content"), "tool_calls": [call]})
                messages.append({"role": "tool", "tool_call_id": call.get("id", call["function"]["name"]), "content": json.dumps(result, ensure_ascii=False)})
            if tool_calls:
                final_payload = {"model": payload["model"], "messages": messages, "tool_choice": "none"}
                final_response = await client.post(f"{settings.deepseek_base_url.rstrip('/')}/chat/completions", headers=headers, json=final_payload)
                final_response.raise_for_status()
                message = final_response.json()["choices"][0]["message"]
    except (httpx.HTTPError, KeyError, IndexError, ValueError) as exc:
        return {"reply": "AI 服务暂时不可用，经营数据仍可继续查看。", "snapshot": snapshot, "tool_results": [], "suggestions": [], "error": str(exc)}
    reply, suggestions = _extract_suggestions(message.get("content") or "分析完成。")
    return {"reply": reply, "snapshot": dashboard_snapshot(db), "tool_results": tool_results, "suggestions": suggestions}


def _extract_suggestions(content: str) -> tuple[str, list[str]]:
    """Keep the model protocol human-readable while exposing choices to the app."""
    lines = content.splitlines()
    suggestions: list[str] = []
    kept: list[str] = []
    for line in lines:
        match = re.match(r"^\s*(?:QUICK_OPTIONS|快捷选项)\s*[:：]\s*(.+?)\s*$", line, re.IGNORECASE)
        if not match:
            kept.append(line)
            continue
        for value in re.split(r"\s*[|｜]\s*", match.group(1)):
            value = value.strip(" \t·•-")
            if value and value not in suggestions:
                suggestions.append(value)
        if len(suggestions) >= 4:
            suggestions = suggestions[:4]
    return "\n".join(kept).strip(), suggestions
