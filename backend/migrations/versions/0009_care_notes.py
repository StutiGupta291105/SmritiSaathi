"""care notes between the caregiver and the doctor of a patient

Revision ID: 0009
Revises: 0008
Create Date: 2026-11-06 09:00:00
"""
from alembic import op
import sqlalchemy as sa


revision = '0009'
down_revision = '0008'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('care_notes',
        sa.Column('id', sa.String(length=36), nullable=False),
        sa.Column('patient_id', sa.String(length=36), nullable=False),
        sa.Column('author_id', sa.String(length=36), nullable=False),
        sa.Column('author_name', sa.String(length=120), nullable=False),
        sa.Column('author_role', sa.String(length=12), nullable=False),
        sa.Column('body', sa.String(length=500), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('deleted', sa.Boolean(), nullable=False),
        sa.ForeignKeyConstraint(['patient_id'], ['patients.id'], ),
        sa.ForeignKeyConstraint(['author_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_care_notes_patient_id'), 'care_notes', ['patient_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_care_notes_patient_id'), table_name='care_notes')
    op.drop_table('care_notes')
