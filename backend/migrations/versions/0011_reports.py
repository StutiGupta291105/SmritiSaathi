"""reports of objectionable AI answers and chat messages

Revision ID: 0011
Revises: 0010
Create Date: 2026-11-06 14:00:00
"""
from alembic import op
import sqlalchemy as sa


revision = '0011'
down_revision = '0010'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('reports',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('reporter_id', sa.String(length=36), nullable=False),
        sa.Column('kind', sa.String(length=8), nullable=False),
        sa.Column('ref', sa.String(length=64), nullable=False),
        sa.Column('excerpt', sa.String(length=500), nullable=False),
        sa.Column('reason', sa.String(length=120), nullable=False),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_reports_created_at'), 'reports', ['created_at'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_reports_created_at'), table_name='reports')
    op.drop_table('reports')
