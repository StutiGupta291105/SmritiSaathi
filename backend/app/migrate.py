"""Database schema versions (Alembic). In production the app never creates or
changes tables itself: it checks that the database is at the newest version and
refuses to start otherwise, so a deploy cannot half-migrate by accident.

    alembic upgrade head      # run before starting a new version
"""
from pathlib import Path

from alembic.config import Config
from alembic.runtime.migration import MigrationContext
from alembic.script import ScriptDirectory

_ROOT = Path(__file__).resolve().parent.parent


def _config() -> Config:
    cfg = Config(str(_ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(_ROOT / "migrations"))
    return cfg


def head_revision() -> str:
    return ScriptDirectory.from_config(_config()).get_current_head()


def current_revision(engine) -> str | None:
    with engine.connect() as conn:
        return MigrationContext.configure(conn).get_current_revision()


def require_up_to_date(engine) -> None:
    have, want = current_revision(engine), head_revision()
    if have != want:
        raise RuntimeError(
            f"Database schema is at {have or 'nothing'}, expected {want}. "
            "Run `alembic upgrade head` first.")
