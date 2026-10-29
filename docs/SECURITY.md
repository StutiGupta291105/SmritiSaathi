# Security controls and gaps

An honest list of what exists, where, how it is tested, and what is still missing.
It is not a certificate: independent testing is required before real use (see the
end).

## Controls in place

| Area | Control | Where | Test |
|---|---|---|---|
| Login | Phone OTP, 6 digits, 5 minutes, single use, 5 tries then locked | `backend/app/routers/auth.py` | `test_auth.py` |
| Login | Code stored only as a keyed hash; request answer is identical whether or not an account exists | same | `test_auth.py` |
| Abuse | OTP requests limited per phone and per IP per hour (counted in the database, so it holds across instances); per-IP request limit; 1 MB body cap | `auth.py`, `main.py` | `test_auth.py` |
| Sessions | 15-minute access tokens; rotating refresh tokens stored hashed; reuse of an old refresh token ends all sessions of that user | `auth.py`, `security.py` | `test_auth.py` |
| Personal data | Phone numbers are never stored: only a keyed hash (lookup) and the last 4 digits. IPs are stored only keyed-hashed | `security.py`, `models.py` | `test_auth.py::test_phone_numbers_are_never_stored_in_the_clear` |
| Minimal server data | No photos, family contacts, location or reminder labels (medicine names) leave the phone | `models.py` | `test_care.py` |
| Access control | A caretaker or doctor sees a patient only with an **accepted** link **and** the patient's **current** matching consent; withdrawing consent cuts access immediately; unknown or forbidden ids answer 404 | `deps.py` | `test_care.py` |
| Consent | Append-only consent log mirrored from the app; sync needs the `sync` purpose, game results need `gameplay`, reminders need `reminders` | `patients.py` | `test_care.py` |
| Accountability | Hash-chained audit log, with a signed head so that deleting the newest entries is detected; reads of a patient's report by others are logged | `audit.py` | `test_care.py` |
| Audit content | Ids only: no phone numbers, names, or health content | `audit.py` | `test_care.py::test_audit_entries_hold_no_personal_data` |
| Rights | Export of everything held; erasure of the patient, linked data and login | `patients.py` | `test_care.py` |
| Transport and headers | HSTS, `nosniff`, `no-store`, no referrer; no stack traces in errors; API docs disabled in production | `main.py` | `test_auth.py` |
| Configuration | Production refuses to start with default keys, a dev SMS provider or SQLite | `config.py` | `test_auth.py` |
| Container | Runs as an unprivileged user | `backend/Dockerfile` | not built here |
| On the phone | SQLCipher database, key in Keystore/Keychain; consent enforced in the data layer; hashed caregiver PIN with lockout; hash-chained local audit log | `lib/data/` | `test/app_database_test.dart` |

## Known gaps (do not skip)

- **No independent penetration test or VAPT yet.** Required before real users.
- **TLS is not terminated here**: it must be done by the load balancer. Nothing
  forces HTTPS inside the app yet (the app only talks to an `https://` base URL when
  one is configured).
- **The OTP provider is a development stub.** A real SMS provider with Indian DLT
  registration must be added behind `SmsProvider` (see `backend/app/sms.py`).
- **No admin interface and no admin MFA.** Operators use the CLI and the cloud
  console; protect those accounts with MFA.
- **Rate limiting of general requests is per process.** Use a shared store or the
  gateway/WAF when running several instances.
- **Migrations are in place (Alembic)**, with a test that fails if the models change
  without a migration. In production the app refuses to start unless the database is
  at the newest version, so run `alembic upgrade head` as a separate deploy step and
  take a backup first. Downgrades exist but have not been rehearsed on real data.
- **Secrets** come from environment variables. Use a secrets manager and plan key
  rotation: rotating `SMRITI_SECRET_KEY` signs everyone out and invalidates the
  audit head MAC, so re-seal the head as part of rotation.
- **Signed audit head is not enough on its own.** Someone holding both the database
  and the key can rewrite history. Ship `python -m app.cli audit-head` output to a
  separate append-only store (for example write-once object storage in an Indian
  region) at least daily.
- **No push notifications.** Alerts are fetched when a caretaker opens the app.
- **Doctor identity is checked by a person, not a registry.** The registration number
  is self-declared. An operator checks it with the relevant medical council and runs
  `python -m app.cli verify-professional <id>`; patients' link lists then show
  `verified`. The app does not show that badge yet, and there is no automated
  registry lookup.
- **Release signing is optional in the build.** With the four `ANDROID_*` repository
  secrets set, the APK is signed with your key; without them it uses a debug key
  and must not be published. Keep the key store backed up offline: losing it means
  users cannot update the app.
- **Backups, restore drills and disaster recovery** are not designed yet.

## Before real use: checklist

1. Independent VAPT against OWASP API Security Top 10 and, for the app, OWASP MASVS.
2. Complete `docs/INCIDENT_RESPONSE.md` (names, contacts) and run one drill.
3. Real SMS provider; DLT templates approved.
4. Deploy per `docs/DEPLOYMENT.md` in an Indian region with logs kept 180 days.
5. Legal review of the consent notice and the DPDP obligations (children and people
   who cannot give consent themselves, guardian consent, retention periods).
6. Clinical review of every message the app shows about the person's use of it.
