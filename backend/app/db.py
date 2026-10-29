from datetime import datetime, timezone

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from sqlalchemy.pool import StaticPool


def utcnow() -> datetime:
    """Naive UTC, used everywhere so SQLite and PostgreSQL behave the same."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


class Base(DeclarativeBase):
    pass


def make_engine(url: str):
    if url.startswith("sqlite"):
        kwargs = {"connect_args": {"check_same_thread": False}}
        if ":memory:" in url or url == "sqlite://":
            kwargs["poolclass"] = StaticPool
        return create_engine(url, **kwargs)
    return create_engine(url, pool_pre_ping=True)


def make_session_factory(engine, info: dict | None = None):
    return sessionmaker(bind=engine, expire_on_commit=False, autoflush=False,
                        info=info or {})


def add_missing_columns(engine, metadata) -> None:
    """Development and test servers only (production uses Alembic): adds columns
    that a newer version of the code expects to a database made by an older one,
    so a free test database does not have to be thrown away."""
    insp = inspect(engine)
    with engine.begin() as conn:
        for table in metadata.sorted_tables:
            if not insp.has_table(table.name):
                continue
            have = {c["name"] for c in insp.get_columns(table.name)}
            for col in table.columns:
                if col.name in have:
                    continue
                ddl = col.type.compile(dialect=engine.dialect)
                default = ""
                if not col.nullable:
                    default = " DEFAULT ''" if "CHAR" in ddl.upper() else " DEFAULT 0"
                conn.execute(text(
                    f'ALTER TABLE "{table.name}" ADD COLUMN "{col.name}" {ddl}{default}'))
