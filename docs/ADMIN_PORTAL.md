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
  sign-ins, and which person's page was opened (`admin_viewed_user`). The admin is watched too.

## One fixed admin, kept apart from every user
There is exactly **one** admin, with a fixed username and password that you set in the
server's settings. It is not a user account: it is not in the users table, the mobile app
has no admin option, and no API can create, change or list admins. The portal is a
separate desktop application, not a screen inside the app. If no admin password is
configured, the `/v1/admin` routes do not exist at all.

## Setting it up
1. Choose the admin's password (12+ characters) and put it in the server settings. On Render:
   the service's **Environment** tab, add `SMRITI_ADMIN_PASSWORD` (and `SMRITI_ADMIN_USERNAME`
   if you want something other than `admin`). Do **not** put the password in the code or the
   repository. Instead of the plain password you can store a hash:
   `python -m app.cli admin-hash` prints `SMRITI_ADMIN_PASSWORD_HASH=...` (and a secret for the
   optional second factor below).
2. Optional but recommended: set `SMRITI_ADMIN_TOTP_SECRET` to the authenticator-app secret
   so sign-in also needs the six-digit code.
3. Build the desktop app: GitHub > Actions > **Build Admin Portal (desktop)**; download the
   artifact for your system and run it.
4. Sign in with the server address, the username, the password (and the code, if you set a
   secret). Sessions last 30 minutes. Five wrong tries from one address lock that address for
   15 minutes. To change the password, change the setting and restart the server.

## What is now in the access log
Beside sign-ins, writes and report views, the server now records **blocked access attempts**
(`access_denied`: a caregiver or doctor reaching for a patient they are not, or no longer,
linked to). Chat reads are not logged (they happen every few seconds); chat sends are.

## Honest limits
* An admin who also has database access can read or alter data directly; the portal limits
  what the *application* shows, not what a database administrator can do. Keep the
  hash-chain head (`python -m app.cli audit-head`) in a separate append-only store.
* There is a single admin and a single permission level: whoever has the password sees everything the portal shows. Keep it in a password manager, and change it if anyone who knew it leaves.
* The desktop builds are produced by the workflow above; they have not been run on real
  Windows or macOS machines by us.
