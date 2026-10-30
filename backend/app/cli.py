"""Operator commands:

  python -m app.cli verify-audit
  python -m app.cli audit-head
  python -m app.cli list-unverified            doctors waiting for a registration check
  python -m app.cli verify-professional <id>   after checking the doctor's registration
  python -m app.cli unverify-professional <id>
  python -m app.cli send-alerts                push new alerts to caretakers and doctors
  python -m app.cli admin-create <username>    a read-only admin portal account (asks for a password,
                                               prints the authenticator secret once)
  python -m app.cli admin-passwd <username>    new password
  python -m app.cli admin-disable <username>   and admin-enable
  python -m app.cli admin-list
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


def _password() -> str:
    import getpass
    import os
    pw = os.environ.get("SMRITI_ADMIN_PASSWORD") or getpass.getpass("Password (12+ characters): ")
    if len(pw) < 12:
        raise SystemExit("Password must be at least 12 characters.")
    return pw


def _admin_command(db, s, cmd: str, username: str) -> int:
    from .models import AdminUser
    from .security import hash_password, new_totp_secret
    username = username.strip().lower()
    admin = db.execute(select(AdminUser).where(AdminUser.username == username)).scalar_one_or_none() \
        if username else None
    if cmd == "admin-list":
        for a in db.execute(select(AdminUser).order_by(AdminUser.created_at)).scalars():
            print(f"{a.username}  {'disabled' if a.disabled else 'active'}  last sign-in: {a.last_login_at or '-'}")
        return 0
    if cmd == "admin-create":
        if admin is not None:
            print("That username exists.")
            return 1
        secret = new_totp_secret()
        a = AdminUser(username=username, password_hash=hash_password(_password()), totp_secret=secret)
        db.add(a)
        db.flush()
        audit.record(db, "operator", "admin_created", f"admin={a.id}")
        db.commit()
        print("Created. Add this to an authenticator app (shown once):")
        print(f"  secret: {secret}")
        print(f"  otpauth://totp/Smriti%20Sathi%20Admin:{username}?secret={secret}&issuer=Smriti%20Sathi%20Admin")
        return 0
    if admin is None:
        print("No such admin.")
        return 1
    if cmd == "admin-passwd":
        admin.password_hash = hash_password(_password())
        admin.failed_attempts, admin.locked_until = 0, None
    else:
        admin.disabled = cmd == "admin-disable"
    audit.record(db, "operator", cmd.replace("-", "_"), f"admin={admin.id}")
    db.commit()
    print("done")
    return 0


def main(argv: list[str]) -> int:
    cmds = {"verify-audit": 1, "audit-head": 1, "list-unverified": 1,
            "verify-professional": 2, "unverify-professional": 2, "send-alerts": 1,
            "admin-create": 2, "admin-passwd": 2, "admin-disable": 2, "admin-enable": 2,
            "admin-list": 1}
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
        if cmd == "send-alerts":
            from . import dispatch, push
            n = dispatch.send_pending_alerts(db, push.get_provider(s.push_provider))
            db.commit()
            print(f"sent {n}")
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
        if cmd.startswith("admin-"):
            return _admin_command(db, s, cmd, argv[1] if len(argv) > 1 else "")
        return _set_verified(db, argv[1], cmd == "verify-professional")


if __name__ == "__main__":
    sys.exit(main(argv=sys.argv[1:]))
