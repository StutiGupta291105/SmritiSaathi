# Offline first

The patient's phone is complete without a network. The server only adds sharing, chat and
the AI helper, and it never blocks the person from using the app.

## What works with no signal (patient)
Everything on the phone: all six games, levels and progress, reminders and routines with
their notifications (including the 30-minute heads-up), marking medicine taken, calling family, the on-device helper and the profile. Data is in the encrypted
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

## Test server waking up
A free Render server sleeps when idle and takes up to a minute to wake. The app pings it
at start-up, and any request that is still waiting after 8 seconds shows "Connecting... the
server was resting" instead of looking like a failure. The workflow `keep-warm.yml` also
pings it every 10 minutes (it runs once the workflow file is on the default branch).
A paid instance never sleeps.

## Safeguards added
* **Old saved copies expire.** A caregiver's or doctor's saved copy older than 7 days is
  deleted instead of shown, so access that ended while offline is not shown for ever.
* **Photos always fit.** A chat photo over 450 KB is re-encoded (JPEG, scaled down) before it
  is queued; the server limit is 600 KB and a refused message is dropped. If it cannot be
  made to fit the person is told, and nothing is queued.
* **No merge is needed for offline writes.** Chat and game results only append. Consent is an
  append-only log. A routine can be edited only by whoever set it, and deleted by them or
  the patient, so the only clash is delete-versus-edit: the second one gets 404 and a queued
  delete that gets 404 is dropped (`test_edit_and_delete_racing_each_other_end_cleanly`).

## Honest limits
* **Signing in to an existing account always needs internet.** A one-time code proves who is
  signing in, and a new phone has no data until it restores it from the server. (An account
  already signed in on the phone keeps working offline.)
* **Caregivers and doctors must be online to sign up**: their identity and, for doctors, the
  registration check happen on the server.
* **Real people and the full AI need a connection.** Offline, chat messages wait in the queue
  and the on-device helper answers; a full AI model cannot run on the phone.
* **Background push needs Firebase** (see `docs/DEPLOYMENT.md`); local reminders do not.
* **Access withdrawn while a phone is offline** is only noticed when it reaches the server;
  until then the saved copy shows (for at most 7 days).
* Real-phone behaviour (airplane mode, battery saver, killed app) must be checked by hand:
  see `docs/DEVICE_TEST.md`.
