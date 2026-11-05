"""live location shares (latest point only)

Revision ID: 0010
Revises: 0009
Create Date: 2026-11-06 12:00:00
"""
from alembic import op
import sqlalchemy as sa


revision = '0010'
down_revision = '0009'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('live_shares',
        sa.Column('token', sa.String(length=48), nullable=False),
        sa.Column('patient_id', sa.String(length=36), nullable=False),
        sa.Column('first_name', sa.String(length=60), nullable=False),
        sa.Column('lat', sa.Float(), nullable=False),
        sa.Column('lng', sa.Float(), nullable=False),
        sa.Column('accuracy', sa.Float(), nullable=False),
        sa.Column('started_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['patient_id'], ['patients.id'], ),
        sa.PrimaryKeyConstraint('token'),
    )
    op.create_index(op.f('ix_live_shares_patient_id'), 'live_shares', ['patient_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_live_shares_patient_id'), table_name='live_shares')
    op.drop_table('live_shares')
