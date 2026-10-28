"""Operator commands:  python -m app.cli verify-audit | audit-head"""
import sys

from . import audit
from .config import load_settings
from .db import make_engine, make_session_factory


def main(argv: list[str]) -> int:
    if len(argv) != 1 or argv[0] not in ("verify-audit", "audit-head"):
        print(__doc__)
        return 2
    s = load_settings()
    sm = make_session_factory(make_engine(s.database_url), {"audit_key": s.secret_key})
    with sm() as db:
        if argv[0] == "verify-audit":
            ok = audit.verify_chain(db)
            print("audit log OK" if ok else "AUDIT LOG FAILED VERIFICATION")
            return 0 if ok else 1
        print(audit.head_hash(db) or "")
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
