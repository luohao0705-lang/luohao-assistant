"""add recurring debt installment fields"""
from alembic import op
import sqlalchemy as sa

revision = "0003_debt_installments"
down_revision = "0002_operating_system"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("debts") as batch:
        batch.add_column(sa.Column("monthly_payment_cents", sa.Integer(), nullable=True))
        batch.add_column(sa.Column("payment_day", sa.Integer(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("debts") as batch:
        batch.drop_column("payment_day")
        batch.drop_column("monthly_payment_cents")
