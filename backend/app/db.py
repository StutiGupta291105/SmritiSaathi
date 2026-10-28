from datetime import datetime, timezone

from sqlalchemy import create_engine
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
