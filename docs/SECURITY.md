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
- **Push notifications: server side only.** Device tokens, a once-a-day-per-alert dispatcher (`python -m app.cli send-alerts`) and a generic lock-screen message exist and are tested with a fake provider. The Firebase provider is untested against a live project, and the app does not yet register a token (needs the Firebase plugin and `google-services.json`).
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

## Talk to Smriti (AI companion): what to know before turning it on

- **Two styles** (`SMRITI_COMPANION_STYLE`): `assistant` (the default) is a basic AI
  helper that replies in the language the person writes in (all 23 supported
  languages, including Indian languages typed in English letters), keeps them company,
  and gives general health information and general rights and legal information in a
  warm, respectful way. It never diagnoses, never prescribes or changes a dose, says
  clearly that it is a program and not a doctor or lawyer, points to a doctor for
  anything new or lasting, and sends serious signs to 112. `companion` is the earlier,
  stricter chat-only style (no medical or legal topics).
- **Off by default.** The server provider is `dev` (a fixed reply). Set
  `SMRITI_COMPANION_PROVIDER=anthropic`, `ANTHROPIC_API_KEY` and, if you want a
  cheaper model, `SMRITI_COMPANION_MODEL` (`render.yaml` already uses a small model).
  Without a key the server still starts and the app uses its on-device helper. The default model is the most capable
  one, which is the most expensive; measure cost per conversation before launch.
- **Data leaves India.** What the person types goes from our server to Anthropic's
  API, which may process it outside India. The consent text says so and is its own
  purpose (`companion`), off until the person (or guardian) allows it, and withdrawal
  stops it at once. Have counsel confirm the DPDP cross-border position and the
  vendor's retention terms (consider zero-data-retention terms) before real use.
- **Nothing is stored.** Messages and replies are not saved or logged by us. We keep
  only a per-day count (limit 40 answered messages by default) and an audit line
  with no content. Reminder text is never sent; only the kind and time of today's
  reminders, the first name and the date.
- **Emergencies never depend on the model.** Words such as chest pain, a fall or
  wanting to die are matched in code in every supported language, whichever language the app is set to, on the
  phone first and again on the server, and answered with fixed text pointing to 112
  and family. The word lists are short and will miss phrasings: have clinicians and
  native speakers extend them, and test them.
- **The model is steered by a prompt, not guaranteed.** It is told never to
  diagnose, prescribe, quiz memory, or ask for personal details, and to
  warn about requests for money or OTPs. Review real (consented, ideally
  consented-for-review) transcripts in a pilot before wider use; we do not keep any,
  so decide how a pilot would collect them.
- **Refusals and outages** become a gentle fixed reply or the on-device helper. No
  server-side fallback model is configured.
- **Without internet or consent** the on-device helper answers the day, what is next
  and a kind thought, with no data leaving the phone.

## Before real use: checklist

1. Independent VAPT against OWASP API Security Top 10 and, for the app, OWASP MASVS.
2. Complete `docs/INCIDENT_RESPONSE.md` (names, contacts) and run one drill.
3. Real SMS provider; DLT templates approved.
4. Deploy per `docs/DEPLOYMENT.md` in an Indian region with logs kept 180 days.
5. Legal review of the consent notice and the DPDP obligations (children and people
   who cannot give consent themselves, guardian consent, retention periods).
6. Clinical review of every message the app shows about the person's use of it.


## Chat between a patient and their caretaker or doctor

- A conversation is the accepted link between the two. Both sides can read and write
  only while the link is accepted and the patient's matching sharing consent is on;
  withdrawing consent ends the link, and then nobody can open the chat. Anything else
  answers 404 like an unknown id (`chat.py`, `test_chat.py`).
- Text, photos (JPEG/PNG/WebP, 600 KB at most) and voice notes (AAC, 600 KB, 2 minutes)
  are stored in the database table `messages`, not as files. The audit log records that a
  message was sent and its kind, never the content.
- The patient's export lists the messages (media without its bytes); erasing the patient
  deletes the conversation.
- A push notification only says "You have a new message."; it never carries content or
  the sender's name.
- A caretaker or doctor may choose to share a phone number so their patients can call
  from the app (`users.contact_phone`). It is shown only to the patient linked to them.
- Not yet: end-to-end encryption (the server can read messages, like the rest of the
  shared data), message retention limits, and reporting or blocking.
