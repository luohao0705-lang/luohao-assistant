"""initial schema"""
from alembic import op
import sqlalchemy as sa

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None

def upgrade() -> None:
    op.create_table("accounts", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("name", sa.String(120), nullable=False), sa.Column("kind", sa.String(40), nullable=False, server_default="bank"), sa.Column("balance_cents", sa.Integer(), nullable=False, server_default="0"), sa.Column("currency", sa.String(3), nullable=False, server_default="CNY"), sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()))
    op.create_table("projects", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("name", sa.String(160), nullable=False), sa.Column("objective", sa.Text()), sa.Column("status", sa.String(30), nullable=False, server_default="active"), sa.Column("priority", sa.Integer(), nullable=False, server_default="3"), sa.Column("budget_cents", sa.Integer(), nullable=False, server_default="0"), sa.Column("due_on", sa.Date()))
    op.add_column("projects", sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()))
    op.create_table("debts", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("creditor", sa.String(160), nullable=False), sa.Column("principal_cents", sa.Integer(), nullable=False), sa.Column("outstanding_cents", sa.Integer(), nullable=False), sa.Column("due_on", sa.Date()), sa.Column("interest_rate", sa.Numeric(8,4)), sa.Column("status", sa.String(20), nullable=False, server_default="open"), sa.Column("note", sa.Text()), sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()))
    op.create_table("transactions", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("account_id", sa.Integer(), sa.ForeignKey("accounts.id")), sa.Column("project_id", sa.Integer(), sa.ForeignKey("projects.id")), sa.Column("kind", sa.String(20), nullable=False), sa.Column("amount_cents", sa.Integer(), nullable=False), sa.Column("occurred_on", sa.Date(), nullable=False), sa.Column("expected_on", sa.Date()), sa.Column("status", sa.String(20), nullable=False, server_default="confirmed"), sa.Column("counterparty", sa.String(160)), sa.Column("note", sa.Text()), sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()))
    op.create_table("tasks", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("project_id", sa.Integer(), sa.ForeignKey("projects.id")), sa.Column("title", sa.String(240), nullable=False), sa.Column("description", sa.Text()), sa.Column("status", sa.String(30), nullable=False, server_default="todo"), sa.Column("priority", sa.Integer(), nullable=False, server_default="3"), sa.Column("due_on", sa.Date()), sa.Column("blocked_reason", sa.Text()), sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()))
    op.create_table("memories", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("memory_type", sa.String(30), nullable=False, server_default="note"), sa.Column("content", sa.Text(), nullable=False), sa.Column("project_id", sa.Integer(), sa.ForeignKey("projects.id")), sa.Column("embedding_json", sa.Text()), sa.Column("source", sa.String(60)), sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()))
    op.create_table("event_logs", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("event_type", sa.String(80), nullable=False), sa.Column("payload_json", sa.Text(), nullable=False), sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()))
    op.create_table("assistant_actions", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("action_type", sa.String(60), nullable=False), sa.Column("payload_json", sa.Text(), nullable=False), sa.Column("status", sa.String(20), nullable=False, server_default="pending"), sa.Column("result_json", sa.Text()), sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()), sa.Column("resolved_at", sa.DateTime()))

def downgrade() -> None:
    for table in ("assistant_actions", "event_logs", "memories", "tasks", "transactions", "debts", "projects", "accounts"):
        op.drop_table(table)
