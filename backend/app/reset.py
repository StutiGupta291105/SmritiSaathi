"""Makes every table brand new. Used by the operator command (python -m app.cli
reset-database) and by the admin portal's "Clear all data" button.

All rows go (accounts, patients, chats, reminders, game results, consents, tokens,
reports, the audit and access log, everything), the numbering of ids starts again at 1,
and no audit entry is written, so the log starts empty. The tables and the schema version
stay. It cannot be undone, so callers must have asked for it in words."""
import os

from sqlalchemy import text
from sqlalchemy.orm import Session

from .db import Base

CONFIRM_PHRASE = "CLEAR ALL DATA"


def allowed(settings) -> bool:
    """Only on a test server. A production server needs SMRITI_ALLOW_WIPE=1 set on purpose."""
    return (not settings.is_prod) or os.environ.get("SMRITI_ALLOW_WIPE") == "1"


def reset_all(db: Session) -> int:
    """TRUNCATE every table (PostgreSQL) or delete every row and restart numbering
    (SQLite, used in tests). Returns how many tables were reset."""
    tables = list(Base.metadata.sorted_tables)
    if db.get_bind().dialect.name == "postgresql":
        names = ", ".join(f'"{t.name}"' for t in tables)
        db.execute(text(f"TRUNCATE TABLE {names} RESTART IDENTITY CASCADE"))
    else:
        for t in reversed(tables):
            db.execute(t.delete())
        try:
            db.execute(text("DELETE FROM sqlite_sequence"))
        except Exception:
            pass  # no autoincrement table in this database
    db.commit()
    return len(tables)
