"""doctor opinion chats and caregiver-doctor chats

Revision ID: 0008
Revises: 0007
Create Date: 2026-11-05 09:00:00
"""
from alembic import op
import sqlalchemy as sa


revision = '0008'
down_revision = '0007'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('conversations',
        sa.Column('id', sa.String(length=36), nullable=False),
        sa.Column('kind', sa.String(length=8), nullable=False),
        sa.Column('patient_id', sa.String(length=36), nullable=False),
        sa.Column('doctor_id', sa.String(length=36), nullable=False),
        sa.Column('caregiver_id', sa.String(length=36), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['patient_id'], ['patients.id'], ),
        sa.ForeignKeyConstraint(['doctor_id'], ['users.id'], ),
        sa.ForeignKeyConstraint(['caregiver_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_conversations_patient_id'), 'conversations', ['patient_id'], unique=False)
    op.create_index(op.f('ix_conversations_doctor_id'), 'conversations', ['doctor_id'], unique=False)
    op.create_index(op.f('ix_conversations_caregiver_id'), 'conversations', ['caregiver_id'], unique=False)
    with op.batch_alter_table('messages') as b:
        b.alter_column('link_id', existing_type=sa.String(length=36), nullable=True)
        b.add_column(sa.Column('conv_id', sa.String(length=36), nullable=True))
        b.create_index(op.f('ix_messages_conv_id'), ['conv_id'], unique=False)
        b.create_foreign_key('fk_messages_conv_id', 'conversations', ['conv_id'], ['id'])


def downgrade() -> None:
    op.execute(sa.text("DELETE FROM messages WHERE conv_id IS NOT NULL"))
    with op.batch_alter_table('messages') as b:
        b.drop_constraint('fk_messages_conv_id', type_='foreignkey')
        b.drop_index(op.f('ix_messages_conv_id'))
        b.drop_column('conv_id')
        b.alter_column('link_id', existing_type=sa.String(length=36), nullable=False)
    op.drop_index(op.f('ix_conversations_caregiver_id'), table_name='conversations')
    op.drop_index(op.f('ix_conversations_doctor_id'), table_name='conversations')
    op.drop_index(op.f('ix_conversations_patient_id'), table_name='conversations')
    op.drop_table('conversations')
