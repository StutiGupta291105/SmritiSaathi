# Admin portal (read only)

A desktop application (Windows, macOS, Linux) for the people who run Smriti Sathi. It is
a database shown as a dashboard: who is in the system, who supervises whom, and what
happened. **It cannot change anything.**

## What it shows
| Page | Content |
|---|---|
| Overview | counts of patients, doctors, caregivers, links, activity and security events (24 h) |
| Patients | every patient, their caregivers and doctors, what they currently share, games played |
| Doctors / Caregivers | Care ID, verified or not, number of patients, last sign-in, joined |
| Supervision | **By supervisor**: each doctor or caregiver with the patients they look after. **All links**: every invitation and its status |
| A person's page (click a row) | account, consents (what is on or off and since when), supervisors or patients, recent log entries |
| Access log | the hash-chained audit log with filters, and a button that checks it is intact |
| Security | wrong sign-in codes, blocked access attempts, reused tokens, failed admin sign-ins, doctors waiting for a registration check, who viewed the most patient reports |

## What it deliberately does not show
Chat messages, photos, voice notes, reminder titles and game answers. The product tells
patients those stay between the people involved, and a monitoring role does not need
them to do its job: the portal shows **that** messages exist (counts per link), never
**what** they say. Phone numbers are not stored in full, so only the last four digits
appear. If an investigation genuinely needs more, it should go through the incident
process in `docs/INCIDENT_RESPONSE.md`, not a standing screen.

## Why it cannot change anything
* Every server endpoint under `/v1/admin` is a GET, apart from the sign-in. A server test
  fails if a writing route is added, and another checks that an admin token gets 401 on
  every patient, care and chat endpoint.
* Admin tokens use a different audience from app tokens: neither works for the other.
* The desktop client's code has one POST (sign-in); a test fails if a PUT, PATCH, DELETE or
  second POST appears. Verifying a doctor stays a command-line operator task.
* The only things the portal writes are log lines about itself: admin sign-ins, failed
  sign-ins, and which person's page was opened (`admin_viewed_user`). Admins are watched too.

## Setting it up
1. On the server, create an admin (needs shell access, so it is never done through the
   API). Use a password of 12+ characters:
   ```
   python -m app.cli admin-create alice
   ```
   It prints an authenticator secret **once**; add it to an authenticator app. Other commands:
   `admin-passwd`, `admin-disable`, `admin-enable`, `admin-list`.
   On Render use the service's Shell tab. In production mode run `alembic upgrade head` first
   (migration 0008 adds the `admin_users` table); in dev mode, as on the Render test
   server, the table is created when the server starts.
2. Build the desktop app: GitHub > Actions > **Build Admin Portal (desktop)** > Run workflow.
   Download the artifact for your system and run it.
3. Sign in with the server address, username, password and the six-digit code. Sessions last
   30 minutes. Five wrong tries lock that account for 15 minutes.

## What is now in the access log
Beside sign-ins, writes and report views, the server now records **blocked access attempts**
(`access_denied`: a caregiver or doctor reaching for a patient they are not, or no longer,
linked to). Chat reads are not logged (they happen every few seconds); chat sends are.

## Honest limits
* An admin who also has database access can read or alter data directly; the portal limits
  what the *application* shows, not what a database administrator can do. Keep the
  hash-chain head (`python -m app.cli audit-head`) in a separate append-only store.
* There is no per-admin permission level yet: every admin sees everything the portal shows.
* The desktop builds are produced by the workflow above; they have not been run on real
  Windows or macOS machines by us.
