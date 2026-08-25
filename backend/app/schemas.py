from __future__ import annotations

from datetime import date

from pydantic import BaseModel, ConfigDict, Field


class LoginRequest(BaseModel):
    password: str = Field(min_length=2, max_length=2, pattern=r"^[0-9]{2}$")


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class AccountCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    kind: str = "bank"
    balance_cents: int = 0
    currency: str = Field(default="CNY", min_length=3, max_length=3)


class TransactionCreate(BaseModel):
    account_id: int | None = None
    project_id: int | None = None
    kind: str = Field(pattern="^(income|expense)$")
    amount_cents: int = Field(gt=0)
    occurred_on: date
    expected_on: date | None = None
    status: str = Field(default="confirmed", pattern="^(planned|confirmed|paid|overdue|cancelled)$")
    counterparty: str | None = Field(default=None, max_length=160)
    note: str | None = None


class TransactionUpdate(BaseModel):
    kind: str | None = Field(default=None, pattern="^(income|expense)$")
    amount_cents: int | None = Field(default=None, gt=0)
    occurred_on: date | None = None
    expected_on: date | None = None
    status: str | None = Field(default=None, pattern="^(planned|confirmed|paid|overdue|cancelled)$")
    counterparty: str | None = Field(default=None, max_length=160)
    note: str | None = None


class DebtCreate(BaseModel):
    creditor: str = Field(min_length=1, max_length=160)
    principal_cents: int = Field(gt=0)
    outstanding_cents: int = Field(ge=0)
    due_on: date | None = None
    monthly_payment_cents: int | None = Field(default=None, ge=0)
    payment_day: int | None = Field(default=None, ge=1, le=31)
    interest_rate: float | None = Field(default=None, ge=0)
    note: str | None = None


class DebtUpdate(BaseModel):
    creditor: str | None = Field(default=None, min_length=1, max_length=160)
    principal_cents: int | None = Field(default=None, gt=0)
    outstanding_cents: int | None = Field(default=None, ge=0)
    due_on: date | None = None
    monthly_payment_cents: int | None = Field(default=None, ge=0)
    payment_day: int | None = Field(default=None, ge=1, le=31)
    interest_rate: float | None = Field(default=None, ge=0)
    status: str | None = Field(default=None, pattern="^(open|paid|overdue|cancelled)$")
    note: str | None = None


class ProjectCreate(BaseModel):
    name: str = Field(min_length=1, max_length=160)
    objective: str | None = None
    priority: int = Field(default=3, ge=1, le=5)
    budget_cents: int = Field(default=0, ge=0)
    due_on: date | None = None
    stage: str = Field(default="planning", max_length=40)
    success_criteria: str | None = None
    key_hypothesis: str | None = None
    risk_summary: str | None = None
    blocker_summary: str | None = None
    next_action: str | None = None


class ProjectUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=160)
    objective: str | None = None
    status: str | None = Field(default=None, pattern="^(planning|active|paused|completed|archived)$")
    priority: int | None = Field(default=None, ge=1, le=5)
    budget_cents: int | None = Field(default=None, ge=0)
    due_on: date | None = None
    stage: str | None = Field(default=None, max_length=40)
    success_criteria: str | None = None
    key_hypothesis: str | None = None
    risk_summary: str | None = None
    blocker_summary: str | None = None
    next_action: str | None = None


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=240)
    description: str | None = None
    project_id: int | None = None
    priority: int = Field(default=3, ge=1, le=5)
    due_on: date | None = None
    impact: int = Field(default=3, ge=1, le=5)
    urgency: int = Field(default=3, ge=1, le=5)
    estimated_minutes: int | None = Field(default=None, ge=5, le=1440)
    waiting_on: str | None = Field(default=None, max_length=240)
    dependency_ids: list[int] = Field(default_factory=list)


class TaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=240)
    description: str | None = None
    status: str | None = Field(default=None, pattern="^(todo|in_progress|done|blocked|cancelled)$")
    priority: int | None = Field(default=None, ge=1, le=5)
    due_on: date | None = None
    blocked_reason: str | None = None
    impact: int | None = Field(default=None, ge=1, le=5)
    urgency: int | None = Field(default=None, ge=1, le=5)
    estimated_minutes: int | None = Field(default=None, ge=5, le=1440)
    waiting_on: str | None = Field(default=None, max_length=240)
    dependency_ids: list[int] | None = None


class DecisionCreate(BaseModel):
    project_id: int | None = None
    title: str = Field(min_length=1, max_length=240)
    context: str | None = None
    decision: str = Field(min_length=1)
    rationale: str | None = None
    review_on: date | None = None


class WeeklyPlanCreate(BaseModel):
    week_start: date
    theme: str | None = Field(default=None, max_length=240)
    outcomes: list[str] = Field(default_factory=list, max_length=5)
    priorities: list[str] = Field(default_factory=list, max_length=8)
    risks: list[str] = Field(default_factory=list, max_length=8)
    review_notes: str | None = None


class AssistantCommand(BaseModel):
    text: str = Field(min_length=1, max_length=8000)
    mode: str = Field(default="chat", pattern="^(chat|finance|plan|execute)$")
    history: list["AssistantHistoryItem"] = Field(default_factory=list, max_length=20)


class AssistantHistoryItem(BaseModel):
    role: str = Field(pattern="^(user|assistant)$")
    content: str = Field(min_length=1, max_length=8000)


class MemoryCreate(BaseModel):
    content: str = Field(min_length=1, max_length=12000)
    memory_type: str = Field(default="note", max_length=30)
    project_id: int | None = None
    source: str = Field(default="manual", max_length=60)


class IdResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int


class ActionResponse(BaseModel):
    id: int
    action_type: str
    status: str
    payload: dict
    result: dict | None = None
