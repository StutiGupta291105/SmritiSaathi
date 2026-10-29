# Quick test server on Render (free, for trying the caregiver app)

**Test only.** `render.yaml` runs the API with `SMRITI_SMS_PROVIDER=test`: no SMS is
sent and every login code is `123456`, so anyone who knows a phone number could log
in as it. Use made-up names and numbers. Production refuses to start with this
setting. The free plan sleeps after 15 minutes without traffic (the first request
afterwards takes about a minute) and the free database expires after 30 days.

1. Sign in at https://render.com with GitHub and allow it to see the repository.
2. New > Blueprint, pick the repository and the branch with `render.yaml`, Apply.
3. Wait until `smriti-api` shows Live. Open `https://<name>.onrender.com/healthz`; it
   should answer `{"status":"ok"}`.
4. In GitHub: repository Settings > Secrets and variables > Actions > Variables >
   New repository variable `API_BASE_URL` = that address (no trailing slash).
5. Run the Build Android APK workflow and install the new APK on both phones.

# Turning on push notifications for new chat messages

The server already sends a push on every new message (`SMRITI_PUSH_PROVIDER=fcm`), and
the app already registers a token when one is available. Two things are yours to do,
because they need your Firebase project:

1. Create a Firebase project, add an Android app with package `in.smritisathi.app`, and
   download `google-services.json`.
2. Create a service-account key (Project settings > Service accounts) and set on the
   server: `SMRITI_PUSH_PROVIDER=fcm`, `SMRITI_FCM_PROJECT_ID`, and
   `SMRITI_FCM_CREDENTIALS_FILE` (plus `pip install google-auth requests`).
3. In the app: add `firebase_core` and `firebase_messaging`, put `google-services.json` in
   `android/app/` (the APK workflow must copy it in), and implement `PushTokenSource`
   with `FirebaseMessaging.instance.getToken()` as described in
   `lib/services/push_service.dart`.

Until then messages still arrive: open chats refresh every few seconds, dashboards and the
patient's home refresh every 20 seconds and show a banner, and unread counts are always
correct. They just do not wake a phone whose app is closed.

# Deployment guide (reference: AWS Mumbai, ap-south-1)

Nothing is deployed yet. This is a reference layout; any Indian region of any
major cloud, or an Indian provider, works the same way. Keep personal data and
logs in India.

## What runs

One container (`backend/Dockerfile`), stateless, plus PostgreSQL.

```
Phone app --HTTPS--> Load balancer (TLS, WAF) --> container(s) --> PostgreSQL
                                                    |
                                                    +--> SMS provider (OTP)
```

## Decisions only you can make

| Decision | Options | Notes |
|---|---|---|
| Hosting account and region | AWS ap-south-1 (Mumbai), Azure Central India, GCP asia-south1 | Keep database, backups and logs in India |
| SMS provider for OTP | MSG91, Twilio, AWS SNS | Needs Indian DLT sender and template registration; add an adapter behind `SmsProvider` |
| Domain name | for example `api.<your-domain>` | The app is built with `--dart-define=API_BASE_URL=https://...` |
| Who runs it | named incident lead and backup | see `docs/INCIDENT_RESPONSE.md` |
| Who may call themselves a doctor | self-declared now | registry check is future work |

## Reference setup on AWS

1. **Database**: RDS PostgreSQL, encrypted with KMS, multi-AZ, automated backups,
   no public access, security group open only to the service.
2. **Service**: ECS Fargate (or any container host) running the image, 2 or more
   tasks, in private subnets.
3. **Edge**: Application Load Balancer with an ACM certificate (TLS 1.2+), AWS WAF
   with the managed rule sets and a rate-based rule. Set `SMRITI_TRUST_PROXY=true`
   only because the load balancer supplies the real client address.
4. **Secrets**: Secrets Manager for `SMRITI_SECRET_KEY`, `SMRITI_PHONE_HMAC_KEY`,
   the database URL and the SMS credentials.
5. **Logs**: CloudWatch Logs in ap-south-1 with retention of at least 180 days;
   S3 object lock (write-once) for the daily audit head.
6. **Time**: use the cloud's time service, which should sync to NIC/NPL sources
   (check the current CERT-In requirement for clock sync).
7. **Monitoring**: alarms for 5xx rate, database CPU and connections, WAF blocks,
   and a daily job that runs `python -m app.cli verify-audit`.

## Environment variables

| Variable | Meaning |
|---|---|
| `SMRITI_ENV` | `prod` turns on the safety checks |
| `SMRITI_SECRET_KEY` | 32+ random characters; signs tokens, hashes codes, signs the audit head |
| `SMRITI_PHONE_HMAC_KEY` | 32+ random characters, different from the above; keyed hash for phone lookups. **Never change it** once users exist: they could no longer log in |
| `SMRITI_DATABASE_URL` | `postgresql+psycopg://user:pass@host/db` |
| `SMRITI_SMS_PROVIDER` | name of the real provider |
| `SMRITI_TRUST_PROXY` | `true` only behind your own proxy |
| `SMRITI_COMPANION_PROVIDER`, `SMRITI_COMPANION_MODEL`, `SMRITI_COMPANION_DAILY_LIMIT`, `ANTHROPIC_API_KEY` | "Talk to Smriti": `dev` (default, fixed reply) or `anthropic`. Read the companion section of `SECURITY.md` first |
| `SMRITI_PUSH_PROVIDER`, `SMRITI_FCM_PROJECT_ID`, `SMRITI_FCM_CREDENTIALS_FILE` | push: `dev` (default) or `fcm`. Needs `pip install google-auth requests` too |
| `SMRITI_OTP_TTL_SECONDS`, `SMRITI_OTP_MAX_ATTEMPTS`, `SMRITI_OTP_PER_HOUR_PHONE`, `SMRITI_OTP_PER_HOUR_IP`, `SMRITI_ACCESS_TTL_MINUTES`, `SMRITI_REFRESH_TTL_DAYS`, `SMRITI_REQUESTS_PER_MINUTE_IP`, `SMRITI_MAX_BODY_BYTES` | tuning, defaults in `backend/app/config.py` |

## Database changes (migrations)

In production the app does not create tables; it refuses to start unless the
database is at the newest version. On every deploy, before starting the new
version (take a backup first):

```
cd backend && alembic upgrade head      # SMRITI_DATABASE_URL must be set
```

When you change `app/models.py`, run `alembic revision --autogenerate -m "what changed"`,
read the generated file, and commit it. A test fails if models and migrations disagree.

## Scheduled jobs

Run `python -m app.cli send-alerts` every 15 to 30 minutes (for example an
EventBridge schedule that starts a one-off container task). It sends at most one
generic push per alert kind per person per day, and does nothing with
`SMRITI_PUSH_PROVIDER=dev`. Also ship `python -m app.cli audit-head` daily (see
`SECURITY.md`).

## Build and run

```
docker build -t smriti-api backend
docker run -p 8000:8000 --env-file prod.env smriti-api
```

Locally, without Docker:

```
cd backend
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
python -m pytest -q
uvicorn app.main:create_app --factory --reload   # docs at /docs in dev
```

## Pointing the app at the server

Build the app with `--dart-define=API_BASE_URL=https://api.example.com`. Without
it the app stays in its offline test mode (fixed OTP `123456`, nothing leaves the
phone). The GitHub APK workflow reads the variable `API_BASE_URL` from the
repository's Actions variables if you set it.
