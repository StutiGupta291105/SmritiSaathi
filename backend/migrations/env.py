import os

from alembic import context
from sqlalchemy import create_engine

from app import models  # noqa: F401  (registers the tables)
from app.config import Settings
from app.db import Base

target_metadata = Base.metadata


def _url() -> str:
    return os.environ.get("SMRITI_DATABASE_URL") or Settings().database_url


def run_migrations_offline() -> None:
    context.configure(url=_url(), target_metadata=target_metadata, literal_binds=True,
                      compare_type=True)
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    # A caller (tests, the app) may hand us an open connection.
    connection = context.config.attributes.get("connection")
    if connection is not None:
        context.configure(connection=connection, target_metadata=target_metadata,
                          compare_type=True)
        with context.begin_transaction():
            context.run_migrations()
        return
    engine = create_engine(_url())
    with engine.connect() as conn:
        context.configure(connection=conn, target_metadata=target_metadata,
                          compare_type=True)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
