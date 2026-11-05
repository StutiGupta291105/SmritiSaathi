"""routines and reminders set by caretakers and doctors

Revision ID: 0007
Revises: 0006
Create Date: 2026-10-30 09:00:00
"""
from alembic import op
import sqlalchemy as sa


revision = '0007'
down_revision = '0006'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('care_reminders',
        sa.Column('id', sa.String(length=36), nullable=False),
        sa.Column('patient_id', sa.String(length=36), nullable=False),
        sa.Column('created_by', sa.String(length=36), nullable=False),
        sa.Column('created_by_name', sa.String(length=120), nullable=False),
        sa.Column('created_by_role', sa.String(length=12), nullable=False),
        sa.Column('kind', sa.String(length=16), nullable=False),
        sa.Column('label', sa.String(length=120), nullable=False),
        sa.Column('hour', sa.Integer(), nullable=False),
        sa.Column('minute', sa.Integer(), nullable=False),
        sa.Column('days_mask', sa.Integer(), nullable=False),
        sa.Column('on_date', sa.String(length=10), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('deleted', sa.Boolean(), nullable=False),
        sa.ForeignKeyConstraint(['patient_id'], ['patients.id'], ),
        sa.ForeignKeyConstraint(['created_by'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_care_reminders_patient_id'), 'care_reminders', ['patient_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_care_reminders_patient_id'), table_name='care_reminders')
    op.drop_table('care_reminders')
