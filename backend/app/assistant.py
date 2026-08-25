import json
import calendar
import re
from datetime import date, timedelta

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import get_settings
from .models import Account, AssistantAction, Debt, EventLog, Memory, Project, Task, Transaction, WeeklyPlan

TOOLS = [
    {"type": "function", "function": {"name": "propose_finance_entry", "description": "Propose an income or expense entry. Use this for recording money; owner confirmation is required before writing.", "parameters": {"type": "object", "properties": {"kind": {"type": "string", "enum": ["income", "expense"]}, "amount_cents": {"type": "integer"}, "occurred_on": {"type": "string"}, "expected_on": {"type": ["string", "null"]}, "counterparty": {"type": ["string", "null"]}, "note": {"type": ["string", "null"]}, "account_id": {"type": ["integer", "null"]}}, "required": ["kind", "amount_cents", "occurred_on"]}}},
    {"type": "function", "function": {"name": "propose_debt_payment", "description": "Propose recording a loan or debt repayment. Match the creditor, record the actual payment as an expense, and reduce the debt outstanding balance. Owner confirmation is required.", "parameters": {"type": "object", "properties": {"creditor": {"type": "string"}, "payment_cents": {"type": "integer"}, "new_outstanding_cents": {"type": ["integer", "null"]}, "occurred_on": {"type": "string"}, "account_id": {"type": ["integer", "null"]}, "note": {"type": ["string", "null"]}}, "required": ["creditor", "payment_cents", "occurred_on"]}}},
    {"type": "function", "function": {"name": "propose_tasks", "description": "Propose tasks; owner confirmation is required. Each task must include a short title.", "parameters": {"type": "object", "properties": {"project_id": {"type": ["integer", "null"]}, "tasks": {"type": "array", "items": {"type": "object", "required": ["title"]}}}, "required": ["tasks"]}}},
    {"type": "function", "function": {"name": "create_project_plan", "description": "Propose a project plan; owner confirmation is required.", "parameters": {"type": "object", "properties": {"name": {"type": "string"}, "objective": {"type": "string"}, "success_criteria": {"type": ["string", "null"]}, "key_hypothesis": {"type": ["string", "null"]}, "risk_summary": {"type": ["string", "null"]}, "next_action": {"type": ["string", "null"]}, "priority": {"type": "integer"}, "due_on": {"type": ["string", "null"]}, "tasks": {"type": "array", "items": {"type": "object"}}}, "required": ["name"]}}},
    {"type": "function", "function": {"name": "create_weekly_plan", "description": "Propose a weekly plan; owner confirmation is required.", "parameters": {"type": "object", "properties": {"week_start": {"type": "string"}, "theme": {"type": ["string", "null"]}, "outcomes": {"type": "array", "items": {"type": "string"}}, "priorities": {"type": "array", "items": {"type": "string"}}, "risks": {"type": "array", "items": {"type": "string"}}}, "required": ["week_start", "outcomes", "priorities"]}}},
    {"type": "function", "function": {"name": "get_daily_focus", "description": "Read today's prioritized command center.", "parameters": {"type": "object", "properties": {}}}},
    {"type": "function", "function": {"name": "get_dashboard", "description": "Read the current operating dashboard.", "parameters": {"type": "object", "properties": {}}}},
]

READ_ONLY_TOOL_NAMES = {"get_dashboard", "get_daily_focus"}
READ_ONLY_TOOLS = [
    tool for tool in TOOLS
    if tool["function"]["name"] in READ_ONLY_TOOL_NAMES
]


def tools_for_mode(mode: str) -> list[dict]:
    """Keep read-only and planning capabilities separate at the API boundary."""
    if mode == "finance":
        return [tool for tool in TOOLS if tool["function"]["name"] in {"propose_finance_entry", "propose_debt_payment"}] + READ_ONLY_TOOLS
    if mode == "plan":
        return TOOLS
    return READ_ONLY_TOOLS


def legacy_debt_transactions(db: Session) -> list[Transaction]:
    """Return old debt entries that were recorded as ordinary expenses.

    Early versions of the assistant stored a debt's remaining balance in a
    confirmed expense transaction. Keep those records readable while the
    dedicated debts table is used for all new entries.
    """
    items = db.scalars(select(Transaction).where(Transaction.kind == "expense")).all()
    return [
        item for item in items
        if is_legacy_debt_transaction(item)
    ]


def is_legacy_debt_transaction(item: Transaction) -> bool:
    return item.kind == "expense" and bool(item.note) and any(
        term in item.note for term in ("欠款", "负债", "债务")
    )


def legacy_monthly_payment_cents(item: Transaction) -> int | None:
    if not item.note:
        return None
    match = re.search(r"每月\s*(?:\d{1,2}\s*[号日])?\s*(?:最低)?(?:还款|还入|还)\s*(\d+(?:\.\d+)?)\s*元", item.note)
    if not match:
        match = re.search(r"每月[^\n]{0,24}?(\d+(?:\.\d+)?)\s*元", item.note)
    return round(float(match.group(1)) * 100) if match else None


def legacy_payment_day(item: Transaction) -> int | None:
    if not item.note:
        return item.expected_on.day if item.expected_on else None
    match = re.search(r"每月\s*(\d{1,2})\s*[号日]", item.note)
    return int(match.group(1)) if match else (item.expected_on.day if item.expected_on else None)


def debt_monthly_payment_cents(debt: Debt) -> int | None:
    return debt.monthly_payment_cents


def monthly_payment_date(payment_day: int | None, fallback: date | None, year: int, month: int) -> date | None:
    day = payment_day or (fallback.day if fallback else None)
    if not day:
        return None
    return date(year, month, min(day, calendar.monthrange(year, month)[1]))


def scheduled_payment_date(debt: Debt, year: int, month: int) -> date | None:
    return monthly_payment_date(debt.payment_day, debt.due_on, year, month)


def legacy_scheduled_payment_date(item: Transaction, year: int, month: int) -> date | None:
    return monthly_payment_date(legacy_payment_day(item), item.expected_on, year, month)


def open_debts(db: Session) -> tuple[list[Debt], list[Transaction]]:
    return (
        db.scalars(select(Debt).where(Debt.status == "open")).all(),
        [item for item in legacy_debt_transactions(db) if item.status not in {"paid", "cancelled"}],
    )


def _date(value: str | None) -> date | None:
    return date.fromisoformat(value) if value else None


def cashflow_forecast(db: Session, days: int = 90) -> list[dict]:
    accounts = db.scalars(select(Account)).all()
    transactions = db.scalars(select(Transaction)).all()
    debts, legacy_debts = open_debts(db)
    balance = available_cash_cents(accounts, transactions)
    today = date.today()
    points: list[dict] = []
    for offset in range(days + 1):
        current = today + timedelta(days=offset)
        for item in transactions:
            event_date = item.expected_on or item.occurred_on
            if event_date == current and item.status == "planned":
                balance += item.amount_cents if item.kind == "income" else -item.amount_cents
        for debt in debts:
            if scheduled_payment_date(debt, current.year, current.month) == current:
                balance -= debt_monthly_payment_cents(debt) or 0
        for debt in legacy_debts:
            if legacy_scheduled_payment_date(debt, current.year, current.month) == current:
                balance -= legacy_monthly_payment_cents(debt) or 0
        points.append({"date": current.isoformat(), "balance_cents": balance})
    return points


def available_cash_cents(accounts: list[Account], transactions: list[Transaction]) -> int:
    """Current cash = account balances plus confirmed standalone entries.

    Entries linked to an account are assumed to be reflected by that account's
    current balance. AI-created entries without an account still need to affect
    the command center immediately.
    """
    account_balance = sum(item.balance_cents for item in accounts)
    standalone = sum(
        item.amount_cents if item.kind == "income" else -item.amount_cents
        for item in transactions
        if item.account_id is None and item.status in {"confirmed", "paid"}
        and not is_legacy_debt_transaction(item)
    )
    return account_balance + standalone


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
    transactions = db.scalars(select(Transaction)).all()
    debts, legacy_debts = open_debts(db)
    projects = db.scalars(select(Project).where(Project.status.in_(["planning", "active", "paused"]))).all()
    tasks = db.scalars(select(Task).where(Task.status.in_(["todo", "in_progress", "blocked"]))).all()
    today = date.today()
    cash_cents = available_cash_cents(accounts, transactions)
    outstanding_debt_cents = sum(item.outstanding_cents for item in debts) + sum(item.amount_cents for item in legacy_debts)
    planned_income = sum(item.amount_cents for item in transactions if item.kind == "income" and item.status == "planned" and (item.expected_on or item.occurred_on) >= today)
    planned_expense = sum(item.amount_cents for item in transactions if item.kind == "expense" and item.status == "planned" and (item.expected_on or item.occurred_on) >= today)
    due_soon = sum(
        debt_monthly_payment_cents(item) or 0
        for item in debts
        if (scheduled := scheduled_payment_date(item, today.year, today.month)) and 0 <= (scheduled - today).days <= 30
    )
    due_soon += sum(
        legacy_monthly_payment_cents(item) or 0
        for item in legacy_debts
        if (scheduled := legacy_scheduled_payment_date(item, today.year, today.month)) and 0 <= (scheduled - today).days <= 30
    )
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


def dashboard_snapshot_for_ai(snapshot: dict) -> dict:
    """Expose monetary values to the model as yuan, never raw integer cents."""
    converted: dict = {}
    for key, value in snapshot.items():
        if key.endswith("_cents") and isinstance(value, (int, float)):
            converted[f"{key[:-6]}_yuan"] = round(value / 100, 2)
        else:
            converted[key] = value
    return converted


def _pending_action(action_type: str, arguments: dict, db: Session) -> dict:
    action = AssistantAction(action_type=action_type, payload_json=json.dumps(arguments, ensure_ascii=False), status="pending")
    db.add(action)
    db.add(EventLog(event_type="assistant.action.proposed", payload_json=json.dumps({"action_type": action_type, "payload": arguments}, ensure_ascii=False)))
    db.commit()
    db.refresh(action)
    return {"pending_action_id": action.id, "status": "pending_confirmation", "action_type": action_type}


def execute_tool(name: str, arguments: dict, db: Session) -> dict:
    if name == "get_dashboard":
        return dashboard_snapshot_for_ai(dashboard_snapshot(db))
    if name == "get_daily_focus":
        return daily_focus_snapshot(db)
    if name in {"propose_finance_entry", "propose_debt_payment", "propose_tasks", "create_project_plan", "create_weekly_plan"}:
        return _pending_action(name, arguments, db)
    return {"error": f"unsupported tool: {name}"}


async def run_assistant(text: str, mode: str, db: Session, history: list[dict] | None = None) -> dict:
    settings = get_settings()
    is_planning = mode in {"plan", "finance"}
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
    pending = db.scalars(select(AssistantAction).where(AssistantAction.status == "pending").order_by(AssistantAction.id.desc()).limit(5)).all()
    pending_context = [
        {"id": item.id, "action_type": item.action_type, "payload": json.loads(item.payload_json)}
        for item in pending
    ]
    messages = [
        {"role": "system", "content": "你是创业者的经营助理。只使用提供的数据，先给出最重要的判断，明确假设和阻塞点。对于查看数据、解释风险、回答事实问题，直接回答，不要加确认流程。涉及登记收入、支出、收款、付款或账户金额时，必须使用 propose_finance_entry；涉及已经偿还贷款或债务时，必须使用 propose_debt_payment，不能用事项工具代替。当用户要求安排、拆解、创建或推进事项时，如果信息足够，不要反问或讲流程，直接给出一份简洁的《待确认方案》，至少包含：目标、具体执行、时间或顺序、主要风险。所有写入必须先生成待确认方案，未经确认不能声称已经写入。方案结尾固定写：确认此方案后，我会立即正式写入。请回复“确认”或告诉我需要修改的地方。只有缺少会改变方案的关键条件时才提问，一次只问一个关键问题，并提供 2-4 个可点击选项。用户提出修改时，基于上一份方案直接给出修订版，不要重新问已经回答过的问题。当你需要用户选择时，在回复最后单独一行输出 QUICK_OPTIONS: 选项1 | 选项2 | 选项3，最多 4 个选项；没有选择必要时不要输出这一行。请始终使用简洁、自然的中文回答。"},
        {"role": "system", "content": json.dumps({"dashboard": dashboard_snapshot_for_ai(snapshot), "daily_focus": daily_focus, "accounts": [{"id": item.id, "name": item.name, "balance_yuan": round(item.balance_cents / 100, 2)} for item in db.scalars(select(Account).order_by(Account.id.asc()).limit(20)).all()], "debts": [{"id": item.id, "creditor": item.creditor, "outstanding_yuan": round(item.outstanding_cents / 100, 2), "monthly_payment_yuan": round((debt_monthly_payment_cents(item) or 0) / 100, 2)} for item in open_debts(db)[0]], "memories": memory_context, "pending_actions": pending_context}, ensure_ascii=False)},
        {"role": "system", "content": (
            ("当前是财务模式。只处理收入、支出、债务和账户登记，必须使用 propose_finance_entry 生成待确认方案；不要创建事项或项目。任何写入都必须等待用户确认。"
             if mode == "finance" else
             "当前是规划模式。只处理事项、项目和周计划；涉及收入、支出、债务或账户时请提示切换到财务模式。任何写入都必须等待用户确认。")
            if is_planning else
            "当前是问答模式。此模式只允许查询和分析，不得创建、修改或登记任何数据；如果用户要求写入或做规划，请明确提示切换到规划模式。"
        )},
        {"role": "system", "content": "经营数据中所有以 _yuan 结尾的金额均已换算为人民币元。必须按原值回答，不得再乘以 100，也不得把元解释为分。"},
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
    available_tools = tools_for_mode(mode)
    # DeepSeek reasoner currently rejects function calling requests on some
    # deployments. Planning must be able to create a pending action, so use
    # the tool-capable chat model for both modes.
    payload = {
        "model": settings.deepseek_chat_model,
        "messages": messages,
        "tools": available_tools,
        "tool_choice": "required" if is_planning else "auto",
    }
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


async def morning_brief(db: Session) -> dict:
    """Build a short, read-only morning brief from current finance and work data."""
    snapshot = dashboard_snapshot(db)
    focus = daily_focus_snapshot(db)
    projects = db.scalars(select(Project).where(Project.status.in_(["planning", "active", "paused"])).order_by(Project.priority.desc()).limit(6)).all()
    debts, _ = open_debts(db)
    context = {
        "dashboard": dashboard_snapshot_for_ai(snapshot),
        "today_focus": focus,
        "projects": [{"name": item.name, "next_action": item.next_action, "open_tasks": len([task for task in item.tasks if task.status in {"todo", "in_progress", "blocked"}])} for item in projects],
        "debts": [{"creditor": item.creditor, "outstanding_yuan": round(item.outstanding_cents / 100, 2), "monthly_payment_yuan": round((debt_monthly_payment_cents(item) or 0) / 100, 2)} for item in debts],
    }
    fallback = {
        "summary": f"当前有 {focus['open_count']} 项未完成事项，{len(projects)} 个进行中的项目；财务数据请以财务页的明细为准。",
        "advice": ["先处理今日优先级最高的事项", "核对未来 7 天的现金与还款安排"],
        "date": date.today().isoformat(),
    }
    settings = get_settings()
    if not settings.deepseek_api_key:
        return fallback
    prompt = "请根据以下创业者经营数据生成一份极简中文早间经营简报。只输出 JSON，不要 Markdown：{\"summary\":\"不超过100字，概括财务安全、工作进展和最大风险\",\"advice\":[\"2-4条今天可执行建议，每条不超过30字\"]}。金额字段已经是人民币元，不要换算。数据：" + json.dumps(context, ensure_ascii=False)
    payload = {"model": settings.deepseek_chat_model, "messages": [{"role": "system", "content": "你是创业者的经营顾问，只根据给定数据，不臆测金额。"}, {"role": "user", "content": prompt}], "temperature": 0.2}
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(f"{settings.deepseek_base_url.rstrip('/')}/chat/completions", headers={"Authorization": f"Bearer {settings.deepseek_api_key}", "Content-Type": "application/json"}, json=payload)
            response.raise_for_status()
            content = response.json()["choices"][0]["message"].get("content") or ""
            parsed = json.loads(content.strip().strip("`").removeprefix("json").strip())
            summary = str(parsed.get("summary") or fallback["summary"])
            advice = [str(item) for item in parsed.get("advice", []) if str(item).strip()][:4]
            return {"summary": summary, "advice": advice or fallback["advice"], "date": date.today().isoformat()}
    except (httpx.HTTPError, KeyError, IndexError, ValueError, TypeError):
        return fallback


async def morning_brief_v2(db: Session) -> dict:
    """Return a structured daily brief with separate life, finance, and work advice."""
    snapshot = dashboard_snapshot(db)
    focus = daily_focus_snapshot(db)
    projects = db.scalars(select(Project).where(Project.status.in_(["planning", "active", "paused"])).order_by(Project.priority.desc()).limit(6)).all()
    debts, _ = open_debts(db)
    context = {
        "dashboard": dashboard_snapshot_for_ai(snapshot),
        "today_focus": focus,
        "projects": [{"name": item.name, "next_action": item.next_action, "open_tasks": len([task for task in item.tasks if task.status in {"todo", "in_progress", "blocked"}])} for item in projects],
        "debts": [{"creditor": item.creditor, "outstanding_yuan": round(item.outstanding_cents / 100, 2), "monthly_payment_yuan": round((debt_monthly_payment_cents(item) or 0) / 100, 2)} for item in debts],
    }
    fallback = {
        "summary": f"当前有 {focus['open_count']} 项未完成事项，{len(projects)} 个进行中的项目。现金预测请重点查看最低余额日期。",
        "life_advice": ["今天只保留一个明确的核心结果，给自己留出处理突发问题的时间。"],
        "finance_advice": ["查看未来 7 天的还款与计划支出，确认最低现金余额能够覆盖。"],
        "work_advice": ["先处理今日优先级最高的事项，再推进一个项目的下一步。"],
        "date": date.today().isoformat(),
    }
    settings = get_settings()
    if not settings.deepseek_api_key:
        return fallback
    prompt = "请根据以下创业者经营数据生成一份极简中文早间经营简报。只输出 JSON，不要 Markdown：{\"summary\":\"不超过100字，明确当前状态和最大风险\",\"life_advice\":[\"1-2条人生与精力建议\"],\"finance_advice\":[\"1-3条财务建议\"],\"work_advice\":[\"1-3条工作与项目建议\"]}。涉及现金预测时必须写清未来预测窗口内的最低现金余额、金额、日期；负数才称为现金缺口，不能把某一天的余额说成当天要支付的金额。金额字段已经是人民币元，不要换算。数据：" + json.dumps(context, ensure_ascii=False)
    payload = {"model": settings.deepseek_chat_model, "messages": [{"role": "system", "content": "你是创业者的经营顾问，只根据给定数据，不臆测金额；建议要具体、短、可执行。"}, {"role": "user", "content": prompt}], "temperature": 0.2}
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(f"{settings.deepseek_base_url.rstrip('/')}/chat/completions", headers={"Authorization": f"Bearer {settings.deepseek_api_key}", "Content-Type": "application/json"}, json=payload)
            response.raise_for_status()
            content = response.json()["choices"][0]["message"].get("content") or ""
            parsed = json.loads(content.strip().strip("`").removeprefix("json").strip())
            def items(key: str) -> list[str]:
                return [str(item).strip() for item in parsed.get(key, []) if str(item).strip()][:3]
            return {"summary": str(parsed.get("summary") or fallback["summary"]), "life_advice": items("life_advice") or fallback["life_advice"], "finance_advice": items("finance_advice") or fallback["finance_advice"], "work_advice": items("work_advice") or fallback["work_advice"], "date": date.today().isoformat()}
    except (httpx.HTTPError, KeyError, IndexError, ValueError, TypeError):
        return fallback


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
