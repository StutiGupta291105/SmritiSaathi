# Offline first

The patient's phone is complete without a network. The server only adds sharing, chat and
the AI helper, and it never blocks the person from using the app.

## What works with no signal (patient)
Everything on the phone: all six games, levels and progress, reminders and routines with
their notifications (including the 30-minute heads-up), marking medicine taken, the water
tracker, calling family, the on-device helper and the profile. Data is in the encrypted
database on the phone first; the server gets a copy only for what the patient agreed to
share, and only when a connection exists.

## What waits, and how
| Done offline | What happens |
|---|---|
| Games played, medicine marked taken | Saved on the phone, sent in the next sync, never sent twice |
| Consent changes, including withdrawals | Queued and sent first at the next sync |
| Inviting a caregiver or doctor by Care ID | Queued; sent when online |
| Deleting a routine a caregiver set | Queued; sent, and not copied back |
| Chat messages (text, photo, voice note) | Shown as "Waiting to send", kept in the encrypted database (so they survive closing the app), sent in order as soon as any request gets through |
| A message the server refuses for good (the link ended) | Dropped, so it cannot block the queue |

A bar at the top says "You are offline. Everything is saved on this phone..." and counts
what is waiting. Coming back online is detected from the first call that works; the phone
then syncs straight away instead of waiting for its timer.

## Caregivers and doctors
They need live data, but the last dashboard, patient list, reports, requests and
conversations are saved on the phone (encrypted) and shown, marked "Showing saved
information from <time>", when the signal drops. Replies written offline are queued like
the patient's messages. Log out wipes everything saved and queued.

## First sign-up with no internet
A new **patient** can tap "Set up without internet" and start at once. The phone number
is checked later, from Settings > Connect online services; that is when sharing, chat and
the AI helper start. Their games, reminders and progress are kept and synced. Caregivers
and doctors must be online to sign up (their whole job is online). There is no offline
login for an existing account: a one-time code proves who is signing in.

## Tests
* `test/offline_layer_test.dart`: cache and outbox in the API client (switchable network).
* `test/offline_ui_test.dart`: waiting messages, saved conversations, the offline bar,
  offline sign-up and connect-later.
* `test/sync_service_test.dart`: a whole session offline, then synced once.
* `test_e2e/offline_flow_test.dart`: the real app code against a real server, with a real
  database file, the network switched off and on, an app restart in between, and a
  caregiver losing signal. Instructions are at the top of the file.

## Honest limits
Two people editing the same thing offline at once is not merged (chat and results only
ever append, so they cannot clash). Photos are saved in the queue uncompressed beyond the
app's own resize. The saved-data copy shows what was last seen. If the patient has withdrawn access, the
next refresh that reaches the server is refused and the saved copy is deleted; until the
phone reaches the server it cannot know. Background push still needs Firebase.
