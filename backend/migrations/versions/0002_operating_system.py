"""operating system planning entities"""
from alembic import op
import sqlalchemy as sa

revision = "0002_operating_system"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("projects") as batch:
        batch.add_column(sa.Column("stage", sa.String(40), nullable=False, server_default="planning"))
        batch.add_column(sa.Column("success_criteria", sa.Text()))
        batch.add_column(sa.Column("key_hypothesis", sa.Text()))
        batch.add_column(sa.Column("risk_summary", sa.Text()))
        batch.add_column(sa.Column("blocker_summary", sa.Text()))
        batch.add_column(sa.Column("next_action", sa.Text()))
    with op.batch_alter_table("tasks") as batch:
        batch.add_column(sa.Column("impact", sa.Integer(), nullable=False, server_default="3"))
        batch.add_column(sa.Column("urgency", sa.Integer(), nullable=False, server_default="3"))
        batch.add_column(sa.Column("estimated_minutes", sa.Integer()))
        batch.add_column(sa.Column("waiting_on", sa.String(240)))
    op.create_table(
        "task_dependencies",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("task_id", sa.Integer(), sa.ForeignKey("tasks.id"), nullable=False),
        sa.Column("depends_on_task_id", sa.Integer(), sa.ForeignKey("tasks.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_table(
        "decision_records",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("project_id", sa.Integer(), sa.ForeignKey("projects.id")),
        sa.Column("title", sa.String(240), nullable=False),
        sa.Column("context", sa.Text()),
        sa.Column("decision", sa.Text(), nullable=False),
        sa.Column("rationale", sa.Text()),
        sa.Column("review_on", sa.Date()),
        sa.Column("status", sa.String(30), nullable=False, server_default="active"),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_table(
        "weekly_plans",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("week_start", sa.Date(), nullable=False, unique=True),
        sa.Column("theme", sa.String(240)),
        sa.Column("outcomes_json", sa.Text(), nullable=False, server_default="[]"),
        sa.Column("priorities_json", sa.Text(), nullable=False, server_default="[]"),
        sa.Column("risks_json", sa.Text(), nullable=False, server_default="[]"),
        sa.Column("review_notes", sa.Text()),
        sa.Column("status", sa.String(30), nullable=False, server_default="draft"),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table("weekly_plans")
    op.drop_table("decision_records")
    op.drop_table("task_dependencies")
    with op.batch_alter_table("tasks") as batch:
        batch.drop_column("waiting_on")
        batch.drop_column("estimated_minutes")
        batch.drop_column("urgency")
        batch.drop_column("impact")
    with op.batch_alter_table("projects") as batch:
        batch.drop_column("next_action")
        batch.drop_column("blocker_summary")
        batch.drop_column("risk_summary")
        batch.drop_column("key_hypothesis")
        batch.drop_column("success_criteria")
        batch.drop_column("stage")
