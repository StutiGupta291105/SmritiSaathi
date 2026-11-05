"""care ids: caretakers and doctors are invited by ID

Revision ID: 0005
Revises: 0004
Create Date: 2026-10-29 21:00:00
"""
import secrets

from alembic import op
import sqlalchemy as sa


revision = '0005'
down_revision = '0004'
branch_labels = None
depends_on = None

_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


def upgrade() -> None:
    op.add_column('users', sa.Column('care_id', sa.String(length=12), nullable=True))
    op.create_index(op.f('ix_users_care_id'), 'users', ['care_id'], unique=False)
    op.add_column('links', sa.Column('invitee_care_id', sa.String(length=12), nullable=True))
    op.create_index(op.f('ix_links_invitee_care_id'), 'links', ['invitee_care_id'], unique=False)
    # Give everyone who already has an account an ID.
    conn = op.get_bind()
    users = sa.table('users', sa.column('id', sa.String), sa.column('role', sa.String),
                     sa.column('care_id', sa.String))
    used = set()
    for uid, role in conn.execute(
            sa.select(users.c.id, users.c.role).where(users.c.role != 'patient')).all():
        while True:
            cid = ("DR-" if role == "doctor" else "CG-") + "".join(
                secrets.choice(_ALPHABET) for _ in range(6))
            if cid not in used:
                used.add(cid)
                break
        conn.execute(users.update().where(users.c.id == uid).values(care_id=cid))


def downgrade() -> None:
    op.drop_index(op.f('ix_links_invitee_care_id'), table_name='links')
    op.drop_column('links', 'invitee_care_id')
    op.drop_index(op.f('ix_users_care_id'), table_name='users')
    op.drop_column('users', 'care_id')
