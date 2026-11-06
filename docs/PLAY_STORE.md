# Publishing on Google Play: what the code does, and what only you can do

This lists the Play policies that apply to Smriti Sathi, what is already built in, and the
steps in the Play Console that need your developer account. Nothing here can be done for you
from the code: the Console forms are legal declarations made by the app's publisher.

## Built into the app and server

| Policy | What is done |
|---|---|
| **App Bundle + target API** | `build-aab.yml` builds the signed `.aab` (target API is Flutter's current default, 35 or newer). Version code = the workflow run number, so it always goes up. |
| **Signing** | Play builds need YOUR key: add repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. The AAB workflow refuses to build without them. The key in `.github/keys/` is a public test key for the APKs you install by hand: never upload anything signed with it. Enrol in Play App Signing. |
| **Privacy policy URL** | The server serves it: `https://<your-server>/privacy`. It is also linked in the app (Profile > Privacy). Set `SMRITI_CONTACT_EMAIL` on the server so a real contact shows on it. |
| **Account deletion (in app and on the web)** | In app: Profile > Privacy > Erase my data. Web URL for the Console: `https://<your-server>/delete-account`. |
| **Permissions kept to the minimum** | Internet, network state, microphone (voice notes), notifications, exact alarms and boot (medicine reminders), vibrate, location (fine/coarse) and foreground service (live location), nothing else. `CALL_PHONE` and `SEND_SMS` are NOT requested: calls and SMS open the phone's own dialer and messaging app with the text ready. No contacts, storage, SMS, call log or background-location permission. |
| **Prominent disclosure for location** | First use of "Are You Lost? Tell Your Loved Ones" shows a clear explanation and records a consent (`location`); it can be withdrawn in Privacy. Location is read only while a share runs. |
| **AI-generated content** | Every Talk to Smriti answer has a flag button ("Report this answer"). The AI helper says it is a program, gives general information only, and sends emergencies to 112. |
| **User-generated content** | Messages between linked people (and doctor opinion chats) can be reported by pressing and holding a message. Reports go to the `reports` table, read with `python -m app.cli reports`, and are deleted with the reporter's account. A patient can end a link at any time in Privacy. |
| **Health apps / medical claims** | The app does not diagnose, treat or monitor, and says so (About, chat note, privacy policy). Keep the store text equally careful (below). |
| **Data security** | HTTPS only (cleartext is off), encrypted on-device database, no cloud backup of it (`allowBackup=false`), short-lived tokens, hashed phone numbers on the server, audit log, rate limits, security headers. |
| **No ads, no tracking SDKs** | None are included. |
| **Exported components** | Only the launcher activity is exported; the notification receivers are not. |

## What you must do in the Play Console

1. **Developer account** (one-time fee) and **identity verification**. If it is a personal account
   created after Nov 2023, Google requires a closed test with 12+ testers for 14 days before production.
2. **Create the app**, category **Health & Fitness** (not Medical, which needs more evidence), free.
3. **Store listing text** - say what it is, not what it cures. Use: "Memory games, daily reminders and
   family/caregiver messaging for people with memory difficulties. Not a medical device. It does not
   diagnose or treat any condition; talk to a doctor about health concerns." Avoid "treat", "cure",
   "prevent dementia", "diagnose", "clinically proven".
4. **App content** forms:
   - *Privacy policy*: the `/privacy` URL.
   - *Data safety*: see the table below.
   - *Target audience*: 18 and over (not for children).
   - *Ads*: no ads.
   - *Content rating* questionnaire: no violence, no gambling, user-to-user messages = yes (moderated by
     report button), location shared with others = yes.
   - *Health apps declaration*: it is a general wellbeing / memory support app, not for diagnosis.
   - *Government / news / financial*: no.
5. **Permission declarations** (Policy > App content):
   - *Foreground service - location*: used to keep sharing the patient's position with their
     caregiver while the screen is off, after the patient presses the button. Provide the short video
     Google asks for (press the card, lock the phone, show the notification and the caregiver's map).
   - *Exact alarms*: medicine and appointment reminders must ring at the exact time.
   - *Location*: only on a user's tap, to tell loved ones where they are.
6. **Test access for the reviewer**: the server in test mode accepts the fixed code `123456`
   (`SMRITI_SMS_PROVIDER=test`). For the review give two ready accounts (a patient and a caregiver) and
   say that. Production must use a real SMS provider (the server refuses to start in prod without one).
7. **Production server**: PostgreSQL, a real SMS provider with India DLT templates, `SMRITI_ENV=prod`,
   `SMRITI_CONTACT_EMAIL`, backups. See DEPLOYMENT.md. The Render free test server sleeps and is not
   suitable for review or production.
8. Upload the `.aab`, start with **internal testing**, then closed, then production.

## Data safety form: suggested answers

All data is encrypted in transit. Users can request deletion (in app and on the web page).

| Data type | Collected | Shared | Purpose | Optional |
|---|---|---|---|---|
| Name | Yes | With the user's own caregiver/doctor | App functionality, account | No |
| Phone number | Yes (hashed on the server) | No | Account, authentication | No |
| Date of birth (age) | Yes | With care team the user allows | App functionality | Yes |
| Health info (reminders, medicines, game results) | Yes | With care team the user allows | App functionality | Yes |
| Approximate and precise location | Only while sharing | With the people the user picks | App functionality | Yes |
| Photos, voice recordings | Yes (chat attachments, profile photo) | With the chat partner | App functionality | Yes |
| Messages (in-app) | Yes | With the chat partner | App functionality | Yes |
| App interactions (game results) | Yes | With care team the user allows | App functionality | Yes |
| User IDs / device token (push) | Yes | Push service (Firebase) | App functionality | No |
| AI helper questions | Sent, not stored | Processed by the AI provider | App functionality | Yes (consent) |

"Shared" in Google's sense excludes sending to a service provider acting for you (hosting, push, AI);
declare the AI provider as a service provider, and say that no data is sold or used for ads.

## Known limits (be honest on the form)

- Family members' numbers are stored only on the patient's phone; the server never gets them.
- Live-location SMS opens the messaging app and the patient presses send (silent SMS is not allowed
  for sideloaded apps and is restricted on Play). Fully automatic SMS to family needs a server SMS
  provider.
- Translations in 21 of 23 languages are machine drafts: have native speakers review before a
  public launch.
- Nothing has been run on a real phone by the author of this repository except what you test.
