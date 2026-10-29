"""Operator commands:

  python -m app.cli verify-audit
  python -m app.cli audit-head
  python -m app.cli list-unverified            doctors waiting for a registration check
  python -m app.cli verify-professional <id>   after checking the doctor's registration
  python -m app.cli unverify-professional <id>
"""
import sys

from sqlalchemy import select

from . import audit
from .config import load_settings
from .db import make_engine, make_session_factory, utcnow
from .models import Link, User


def _set_verified(db, user_id: str, on: bool) -> int:
    user = db.get(User, user_id)
    if user is None or user.role != "doctor":
        print("No doctor with that id.")
        return 1
    user.verified_at = utcnow() if on else None
    audit.record(db, "operator", "doctor_verified" if on else "doctor_unverified",
                 f"user={user.id}")
    db.commit()
    print("verified" if on else "verification removed")
    return 0


def main(argv: list[str]) -> int:
    cmds = {"verify-audit": 1, "audit-head": 1, "list-unverified": 1,
            "verify-professional": 2, "unverify-professional": 2}
    if not argv or cmds.get(argv[0]) != len(argv):
        print(__doc__)
        return 2
    s = load_settings()
    sm = make_session_factory(make_engine(s.database_url), {"audit_key": s.secret_key})
    with sm() as db:
        cmd = argv[0]
        if cmd == "verify-audit":
            ok = audit.verify_chain(db)
            print("audit log OK" if ok else "AUDIT LOG FAILED VERIFICATION")
            return 0 if ok else 1
        if cmd == "audit-head":
            print(audit.head_hash(db) or "")
            return 0
        if cmd == "list-unverified":
            doctors = db.execute(select(User).where(
                User.role == "doctor", User.verified_at.is_(None))).scalars()
            for d in doctors:
                ids = {l.professional_id for l in db.execute(
                    select(Link).where(Link.member_user_id == d.id)).scalars()
                    if l.professional_id}
                print(f"{d.id}  {d.name}  ***{d.phone_last4}  claimed ids: {', '.join(sorted(ids)) or '-'}")
            return 0
        return _set_verified(db, argv[1], cmd == "verify-professional")


if __name__ == "__main__":
    sys.exit(main(argv=sys.argv[1:]))
