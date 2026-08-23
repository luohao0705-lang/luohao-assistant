import json
from datetime import datetime, timezone

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from .assistant import cashflow_forecast, daily_focus_snapshot, dashboard_snapshot, run_assistant, task_priority_score
from .config import get_settings
from .db import Base, engine, get_db
from .models import Account, AssistantAction, DecisionRecord, Debt, EventLog, Memory, Project, Task, TaskDependency, Transaction, WeeklyPlan
from .schemas import AccountCreate, ActionResponse, AssistantCommand, DebtCreate, DebtUpdate, DecisionCreate, IdResponse, LoginRequest, MemoryCreate, ProjectCreate, ProjectUpdate, TaskCreate, TaskUpdate, TokenResponse, TransactionCreate, TransactionUpdate, WeeklyPlanCreate
from .security import create_access_token, require_auth, verify_password

settings = get_settings()
if settings.app_env.lower() != "production":
    Base.metadata.create_all(bind=engine)
app = FastAPI(title="Luohao Assistant API", version="0.4.0")
app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origin_list, allow_credentials=True, allow_methods=["*"], allow_headers=["*"])


def _task_dependencies(item: Task, db: Session) -> list[int]:
    return db.scalars(select(TaskDependency.depends_on_task_id).where(TaskDependency.task_id == item.id)).all()


def _serialize_task(item: Task, db: Session) -> dict:
    return {
        "id": item.id, "title": item.title, "description": item.description, "status": item.status,
        "priority": item.priority, "impact": item.impact, "urgency": item.urgency,
        "due_on": item.due_on.isoformat() if item.due_on else None, "project_id": item.project_id,
        "blocked_reason": item.blocked_reason, "waiting_on": item.waiting_on, "estimated_minutes": item.estimated_minutes,
        "dependency_ids": _task_dependencies(item, db), "score": task_priority_score(item),
    }


def _serialize_project(item: Project, db: Session, include_tasks: bool = False) -> dict:
    result = {
        "id": item.id, "name": item.name, "objective": item.objective, "status": item.status, "stage": item.stage,
        "priority": item.priority, "budget_cents": item.budget_cents, "due_on": item.due_on.isoformat() if item.due_on else None,
        "success_criteria": item.success_criteria, "key_hypothesis": item.key_hypothesis, "risk_summary": item.risk_summary,
        "blocker_summary": item.blocker_summary, "next_action": item.next_action,
    }
    if include_tasks:
        tasks = db.scalars(select(Task).where(Task.project_id == item.id).order_by(Task.status, Task.priority.desc(), Task.id.desc())).all()
        result["tasks"] = [_serialize_task(task, db) for task in tasks]
        result["open_task_count"] = sum(1 for task in tasks if task.status not in {"done", "cancelled"})
    return result


def _serialize_weekly_plan(item: WeeklyPlan) -> dict:
    return {
        "id": item.id, "week_start": item.week_start.isoformat(), "theme": item.theme,
        "outcomes": json.loads(item.outcomes_json), "priorities": json.loads(item.priorities_json),
        "risks": json.loads(item.risks_json), "review_notes": item.review_notes, "status": item.status,
    }


def _replace_dependencies(task: Task, dependency_ids: list[int], db: Session) -> None:
    valid_ids = sorted(set(item for item in dependency_ids if item != task.id))
    if valid_ids:
        found = set(db.scalars(select(Task.id).where(Task.id.in_(valid_ids))).all())
        missing = set(valid_ids) - found
        if missing:
            raise HTTPException(status_code=422, detail=f"dependency tasks not found: {sorted(missing)}")
        rows = db.execute(select(TaskDependency.task_id, TaskDependency.depends_on_task_id)).all()
        graph: dict[int, set[int]] = {}
        for source, target in rows:
            graph.setdefault(source, set()).add(target)
        graph[task.id] = set(valid_ids)
        for dependency_id in valid_ids:
            stack = [dependency_id]
            visited: set[int] = set()
            while stack:
                current = stack.pop()
                if current == task.id:
                    raise HTTPException(status_code=422, detail="task dependency cycle detected")
                if current in visited:
                    continue
                visited.add(current)
                stack.extend(graph.get(current, ()))
    db.query(TaskDependency).filter(TaskDependency.task_id == task.id).delete(synchronize_session=False)
    db.add_all([TaskDependency(task_id=task.id, depends_on_task_id=dependency_id) for dependency_id in valid_ids])


def _create_task(data: dict, db: Session, default_project_id: int | None = None) -> Task:
    payload = dict(data)
    dependencies = payload.pop("dependency_ids", []) or []
    if payload.get("due_on") and isinstance(payload["due_on"], str):
        from datetime import date
        payload["due_on"] = date.fromisoformat(payload["due_on"])
    payload.setdefault("project_id", default_project_id)
    allowed = {"title", "description", "project_id", "priority", "due_on", "impact", "urgency", "estimated_minutes", "waiting_on"}
    task = Task(**{key: value for key, value in payload.items() if key in allowed})
    db.add(task)
    db.flush()
    _replace_dependencies(task, dependencies, db)
    return task


@app.get("/health")
def health() -> dict:
    return {"ok": True, "service": "luohao-assistant-api"}


@app.get("/health/ready")
def readiness(db: Session = Depends(get_db)) -> dict:
    db.execute(text("SELECT 1"))
    return {"ok": True, "database": "ready"}


@app.post("/auth/login", response_model=TokenResponse)
def login(payload: LoginRequest) -> TokenResponse:
    if not verify_password(payload.password):
        raise HTTPException(status_code=401, detail="invalid password")
    return TokenResponse(access_token=create_access_token())


@app.get("/dashboard/summary")
def dashboard(_: str = Depends(require_auth), db: Session = Depends(get_db)) -> dict:
    return dashboard_snapshot(db)


@app.get("/dashboard/cashflow")
def cashflow(days: int = Query(default=90, ge=7, le=365), _: str = Depends(require_auth), db: Session = Depends(get_db)) -> dict:
    return {"days": days, "points": cashflow_forecast(db, days)}


@app.get("/daily-focus")
def daily_focus(_: str = Depends(require_auth), db: Session = Depends(get_db)) -> dict:
    return daily_focus_snapshot(db)


@app.get("/finance/accounts")
def list_accounts(_: str = Depends(require_auth), db: Session = Depends(get_db)) -> dict:
    items = db.scalars(select(Account).order_by(Account.id.asc()).limit(100)).all()
    return {"items": [{
        "id": item.id, "name": item.name, "kind": item.kind,
        "balance_cents": item.balance_cents, "currency": item.currency,
        "created_at": item.created_at.isoformat() if item.created_at else None,
    } for item in items]}


@app.get("/finance/transactions")
def list_transactions(
    kind: str | None = Query(default=None),
    status: str | None = Query(default=None),
    _: str = Depends(require_auth),
    db: Session = Depends(get_db),
) -> dict:
    query = select(Transaction).order_by(Transaction.occurred_on.desc(), Transaction.id.desc()).limit(200)
    if kind:
        query = query.where(Transaction.kind == kind)
    if status:
        query = query.where(Transaction.status == status)
    items = db.scalars(query).all()
    return {"items": [{
        "id": item.id, "account_id": item.account_id, "project_id": item.project_id,
        "kind": item.kind, "amount_cents": item.amount_cents,
        "occurred_on": item.occurred_on.isoformat(),
        "expected_on": item.expected_on.isoformat() if item.expected_on else None,
        "status": item.status, "counterparty": item.counterparty, "note": item.note,
    } for item in items]}


@app.get("/finance/debts")
def list_debts(status: str | None = Query(default=None), _: str = Depends(require_auth), db: Session = Depends(get_db)) -> dict:
    query = select(Debt).order_by(Debt.due_on.asc().nullslast(), Debt.id.desc()).limit(100)
    if status:
        query = query.where(Debt.status == status)
    items = db.scalars(query).all()
    return {"items": [{
        "id": item.id, "creditor": item.creditor,
        "principal_cents": item.principal_cents, "outstanding_cents": item.outstanding_cents,
        "due_on": item.due_on.isoformat() if item.due_on else None,
        "interest_rate": float(item.interest_rate) if item.interest_rate is not None else None,
        "status": item.status, "note": item.note,
    } for item in items]}


@app.post("/finance/accounts", response_model=IdResponse)
def create_account(payload: AccountCreate, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> IdResponse:
    item = Account(**payload.model_dump())
    db.add(item)
    db.add(EventLog(event_type="account.created", payload_json=payload.model_dump_json()))
    db.commit()
    db.refresh(item)
    return IdResponse(id=item.id)


@app.post("/finance/transactions", response_model=IdResponse)
def create_transaction(payload: TransactionCreate, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> IdResponse:
    item = Transaction(**payload.model_dump())
    db.add(item)
    db.add(EventLog(event_type="transaction.created", payload_json=payload.model_dump_json()))
    db.commit()
    db.refresh(item)
    return IdResponse(id=item.id)


@app.patch("/finance/transactions/{transaction_id}", response_model=IdResponse)
def update_transaction(transaction_id: int, payload: TransactionUpdate, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> IdResponse:
    item = db.get(Transaction, transaction_id)
    if not item:
        raise HTTPException(status_code=404, detail="transaction not found")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, key, value)
    db.add(EventLog(event_type="transaction.updated", payload_json=payload.model_dump_json()))
    db.commit()
    return IdResponse(id=item.id)


@app.post("/finance/debts", response_model=IdResponse)
def create_debt(payload: DebtCreate, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> IdResponse:
    item = Debt(**payload.model_dump())
    db.add(item)
    db.add(EventLog(event_type="debt.created", payload_json=payload.model_dump_json()))
    db.commit()
    db.refresh(item)
    return IdResponse(id=item.id)


@app.patch("/finance/debts/{debt_id}", response_model=IdResponse)
def update_debt(debt_id: int, payload: DebtUpdate, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> IdResponse:
    item = db.get(Debt, debt_id)
    if not item:
        raise HTTPException(status_code=404, detail="debt not found")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, key, value)
    db.add(EventLog(event_type="debt.updated", payload_json=payload.model_dump_json()))
    db.commit()
    return IdResponse(id=item.id)


@app.post("/projects", response_model=IdResponse)
def create_project(payload: ProjectCreate, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> IdResponse:
    item = Project(**payload.model_dump())
    db.add(item)
    db.add(EventLog(event_type="project.created", payload_json=payload.model_dump_json()))
    db.commit()
    db.refresh(item)
    return IdResponse(id=item.id)


@app.get("/projects")
def list_projects(include_archived: bool = False, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> dict:
    query = select(Project).order_by(Project.priority.desc(), Project.due_on.asc().nullslast(), Project.id.desc())
    if not include_archived:
        query = query.where(Project.status != "archived")
    return {"items": [_serialize_project(item, db, include_tasks=True) for item in db.scalars(query.limit(100)).all()]}


@app.get("/projects/{project_id}")
def project_detail(project_id: int, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> dict:
    item = db.get(Project, project_id)
    if not item:
        raise HTTPException(status_code=404, detail="project not found")
    return _serialize_project(item, db, include_tasks=True)


@app.patch("/projects/{project_id}", response_model=IdResponse)
def update_project(project_id: int, payload: ProjectUpdate, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> IdResponse:
    item = db.get(Project, project_id)
    if not item:
        raise HTTPException(status_code=404, detail="project not found")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(item, key, value)
    db.add(EventLog(event_type="project.updated", payload_json=payload.model_dump_json()))
    db.commit()
    return IdResponse(id=item.id)


@app.post("/tasks", response_model=IdResponse)
def create_task(payload: TaskCreate, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> IdResponse:
    item = _create_task(payload.model_dump(), db)
    db.add(EventLog(event_type="task.created", payload_json=payload.model_dump_json()))
    db.commit()
    return IdResponse(id=item.id)


@app.get("/tasks")
def list_tasks(project_id: int | None = None, status_filter: str | None = Query(default=None, alias="status"), _: str = Depends(require_auth), db: Session = Depends(get_db)) -> dict:
    query = select(Task).order_by(Task.due_on.asc().nullslast(), Task.priority.desc(), Task.id.desc())
    if status_filter:
        query = query.where(Task.status == status_filter)
    if project_id is not None:
        query = query.where(Task.project_id == project_id)
    return {"items": [_serialize_task(item, db) for item in db.scalars(query.limit(200)).all()]}


@app.patch("/tasks/{task_id}", response_model=IdResponse)
def update_task(task_id: int, payload: TaskUpdate, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> IdResponse:
    item = db.get(Task, task_id)
    if not item:
        raise HTTPException(status_code=404, detail="task not found")
    values = payload.model_dump(exclude_unset=True)
    dependencies = values.pop("dependency_ids", None)
    for key, value in values.items():
        setattr(item, key, value)
    if dependencies is not None:
        _replace_dependencies(item, dependencies, db)
    db.add(EventLog(event_type="task.updated", payload_json=payload.model_dump_json()))
    db.commit()
    return IdResponse(id=item.id)


@app.post("/decisions", response_model=IdResponse)
def create_decision(payload: DecisionCreate, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> IdResponse:
    item = DecisionRecord(**payload.model_dump())
    db.add(item)
    db.add(EventLog(event_type="decision.created", payload_json=payload.model_dump_json()))
    db.commit()
    db.refresh(item)
    return IdResponse(id=item.id)


@app.get("/decisions")
def list_decisions(project_id: int | None = None, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> dict:
    query = select(DecisionRecord).where(DecisionRecord.status == "active").order_by(DecisionRecord.review_on.asc().nullslast(), DecisionRecord.id.desc())
    if project_id is not None:
        query = query.where(DecisionRecord.project_id == project_id)
    items = db.scalars(query.limit(100)).all()
    return {"items": [{"id": item.id, "project_id": item.project_id, "title": item.title, "context": item.context, "decision": item.decision, "rationale": item.rationale, "review_on": item.review_on.isoformat() if item.review_on else None} for item in items]}


@app.post("/weekly-plans", response_model=IdResponse)
def create_weekly_plan(payload: WeeklyPlanCreate, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> IdResponse:
    item = db.scalar(select(WeeklyPlan).where(WeeklyPlan.week_start == payload.week_start))
    if item:
        item.theme = payload.theme
        item.outcomes_json = json.dumps(payload.outcomes, ensure_ascii=False)
        item.priorities_json = json.dumps(payload.priorities, ensure_ascii=False)
        item.risks_json = json.dumps(payload.risks, ensure_ascii=False)
        item.review_notes = payload.review_notes
    else:
        item = WeeklyPlan(week_start=payload.week_start, theme=payload.theme, outcomes_json=json.dumps(payload.outcomes, ensure_ascii=False), priorities_json=json.dumps(payload.priorities, ensure_ascii=False), risks_json=json.dumps(payload.risks, ensure_ascii=False), review_notes=payload.review_notes)
        db.add(item)
    db.add(EventLog(event_type="weekly_plan.saved", payload_json=payload.model_dump_json()))
    db.commit()
    db.refresh(item)
    return IdResponse(id=item.id)


@app.get("/weekly-plans/current")
def current_weekly_plan(_: str = Depends(require_auth), db: Session = Depends(get_db)) -> dict:
    from datetime import date, timedelta
    today = date.today()
    week_start = today - timedelta(days=today.weekday())
    item = db.scalar(select(WeeklyPlan).where(WeeklyPlan.week_start == week_start))
    return {"item": _serialize_weekly_plan(item) if item else None, "week_start": week_start.isoformat()}


@app.post("/memories", response_model=IdResponse)
def create_memory(payload: MemoryCreate, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> IdResponse:
    item = Memory(**payload.model_dump())
    db.add(item)
    db.add(EventLog(event_type="memory.created", payload_json=payload.model_dump_json()))
    db.commit()
    db.refresh(item)
    return IdResponse(id=item.id)


@app.get("/memories")
def list_memories(include_archived: bool = False, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> dict:
    query = select(Memory).order_by(Memory.id.desc()).limit(200)
    if not include_archived:
        query = query.where(Memory.memory_type != "archived")
    items = db.scalars(query).all()
    return {"items": [{"id": i.id, "memory_type": i.memory_type, "content": i.content, "project_id": i.project_id, "source": i.source, "created_at": i.created_at.isoformat() if i.created_at else None} for i in items]}


@app.post("/memories/{memory_id}/archive", response_model=IdResponse)
def archive_memory(memory_id: int, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> IdResponse:
    item = db.get(Memory, memory_id)
    if not item:
        raise HTTPException(status_code=404, detail="memory not found")
    item.memory_type = "archived"
    db.add(EventLog(event_type="memory.archived", payload_json=json.dumps({"id": memory_id})))
    db.commit()
    return IdResponse(id=item.id)


@app.get("/memories/search")
def search_memories(q: str = Query(min_length=1, max_length=200), _: str = Depends(require_auth), db: Session = Depends(get_db)) -> dict:
    items = db.scalars(select(Memory).where(Memory.content.ilike(f"%{q}%"), Memory.memory_type != "archived").limit(20)).all()
    return {"items": [{"id": item.id, "memory_type": item.memory_type, "content": item.content, "project_id": item.project_id, "source": item.source} for item in items]}


@app.get("/assistant/actions")
def list_actions(status: str | None = Query(default=None), _: str = Depends(require_auth), db: Session = Depends(get_db)) -> dict:
    query = select(AssistantAction).order_by(AssistantAction.id.desc()).limit(50)
    if status:
        query = query.where(AssistantAction.status == status)
    items = db.scalars(query).all()
    return {"items": [{"id": item.id, "action_type": item.action_type, "status": item.status, "payload": json.loads(item.payload_json), "result": json.loads(item.result_json) if item.result_json else None} for item in items]}


def _confirm_action(action: AssistantAction, db: Session) -> dict:
    payload = json.loads(action.payload_json)
    if action.action_type == "propose_tasks":
        task_ids = [_create_task(task_data, db, payload.get("project_id")).id for task_data in payload.get("tasks", [])]
        return {"task_ids": task_ids, "count": len(task_ids)}
    if action.action_type == "create_project_plan":
        project_fields = {key: payload.get(key) for key in ("name", "objective", "success_criteria", "key_hypothesis", "risk_summary", "next_action", "priority") if payload.get(key) is not None}
        if payload.get("due_on"):
            from datetime import date
            project_fields["due_on"] = date.fromisoformat(payload["due_on"])
        project = Project(**project_fields)
        db.add(project)
        db.flush()
        task_ids = [_create_task(task_data, db, project.id).id for task_data in payload.get("tasks", [])]
        return {"project_id": project.id, "task_ids": task_ids}
    if action.action_type == "create_weekly_plan":
        from datetime import date
        week_start = date.fromisoformat(payload["week_start"])
        item = db.scalar(select(WeeklyPlan).where(WeeklyPlan.week_start == week_start))
        if not item:
            item = WeeklyPlan(week_start=week_start)
            db.add(item)
        item.theme = payload.get("theme")
        item.outcomes_json = json.dumps(payload.get("outcomes", []), ensure_ascii=False)
        item.priorities_json = json.dumps(payload.get("priorities", []), ensure_ascii=False)
        item.risks_json = json.dumps(payload.get("risks", []), ensure_ascii=False)
        db.flush()
        return {"weekly_plan_id": item.id, "week_start": week_start.isoformat()}
    raise HTTPException(status_code=400, detail="unsupported action")


@app.post("/assistant/actions/{action_id}/confirm", response_model=ActionResponse)
def confirm_action(action_id: int, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> ActionResponse:
    action = db.get(AssistantAction, action_id)
    if not action or action.status != "pending":
        raise HTTPException(status_code=404, detail="pending action not found")
    payload = json.loads(action.payload_json)
    result = _confirm_action(action, db)
    action.status = "confirmed"
    action.result_json = json.dumps(result, ensure_ascii=False)
    action.resolved_at = datetime.now(timezone.utc)
    db.add(EventLog(event_type="assistant.action.confirmed", payload_json=action.payload_json))
    db.commit()
    return ActionResponse(id=action.id, action_type=action.action_type, status=action.status, payload=payload, result=result)


@app.post("/assistant/actions/{action_id}/cancel", response_model=ActionResponse)
def cancel_action(action_id: int, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> ActionResponse:
    action = db.get(AssistantAction, action_id)
    if not action or action.status != "pending":
        raise HTTPException(status_code=404, detail="pending action not found")
    payload = json.loads(action.payload_json)
    action.status = "cancelled"
    action.resolved_at = datetime.now(timezone.utc)
    db.add(EventLog(event_type="assistant.action.cancelled", payload_json=action.payload_json))
    db.commit()
    return ActionResponse(id=action.id, action_type=action.action_type, status=action.status, payload=payload)


@app.post("/assistant/command")
async def assistant_command(payload: AssistantCommand, _: str = Depends(require_auth), db: Session = Depends(get_db)) -> dict:
    history = [item.model_dump() for item in payload.history]
    return await run_assistant(payload.text, payload.mode, db, history)
