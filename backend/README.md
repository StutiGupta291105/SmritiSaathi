# Smriti Sathi API

FastAPI + SQLAlchemy. See `docs/SECURITY.md` for the controls and
`docs/DEPLOYMENT.md` to run it.

```
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
python -m pytest -q
uvicorn app.main:create_app --factory --reload
```

| Endpoint | Who | What |
|---|---|---|
| `POST /v1/auth/otp/request`, `/otp/verify`, `/refresh`, `/logout` | anyone | phone OTP login, `mode: login or signup` |
| `GET /v1/auth/me` | any signed-in | who am I |
| `POST /v1/patients`, `GET /v1/patients/me` | patient | the patient profile |
| `POST/GET /v1/patients/{id}/consents` | patient | append / read consent decisions |
| `POST /v1/patients/{id}/invites`, `GET .../links` | patient | invite a caretaker or doctor, list links |
| `GET /v1/invites`, `POST /v1/invites/{id}/accept`, `/decline` | caretaker, doctor | answer an invite |
| `DELETE /v1/links/{id}` | patient or the member | end a link |
| `POST /v1/patients/{id}/sync` | patient | idempotent upload of results, reminder timings, done marks |
| `GET /v1/patients/{id}/report?days=7\|30\|90` | patient, or linked member with consent | report and alerts |
| `GET /v1/my-patients` | caretaker, doctor | patients visible now, with alert counts |
| `PATCH /v1/patients/{id}/baseline` | patient or linked caretaker | starting level |
| `GET /v1/patients/{id}/export`, `DELETE /v1/patients/{id}` | patient | access and erasure |

Operator commands: `python -m app.cli verify-audit`, `python -m app.cli audit-head`.
