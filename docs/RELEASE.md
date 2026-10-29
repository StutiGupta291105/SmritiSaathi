# Release guide (Android and iOS)

Everything here is a draft for you and your reviewers. Store policies, privacy-label
categories and legal wording change; confirm each item against the current store
pages and with counsel before submitting.

## 1. Build artefacts

| | Android | iOS |
|---|---|---|
| Workflow | `build-apk.yml` (works, produces an APK) | `build-ios.yml` (**not yet run**; builds unsigned, cannot be installed) |
| Signing | optional: set `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` secrets. Without them the APK uses a debug key and **must not be published** | needs an Apple Developer Program account (paid), a distribution certificate and a provisioning profile; add a signing step once you have them |
| Store format | Play wants an **AAB** (`flutter build appbundle`): add that step before the first Play upload | App Store wants an **IPA** uploaded through Xcode or `xcrun altool`/Transporter, then TestFlight |
| Server address | repository variable `API_BASE_URL` (HTTPS only) | same variable |

First run of the iOS workflow will probably need small fixes (pod versions, a plugin
needing a newer iOS target). Run it, read the log, and iterate before relying on it.

Keep the Android key store backed up offline. If it is lost, existing users cannot
receive updates.

## 2. What the app collects (for the store privacy forms)

Declare **conservatively**; under-declaring is the usual cause of rejection.
Collected only when the person has signed in to the server and allowed sharing:

| Data | Where it goes | Linked to the person | Used for |
|---|---|---|---|
| Name, mobile number (stored on the server only as a keyed hash plus last 4 digits) | our server (India) | yes | account, login by OTP, invites |
| Game results (game, levels, correct/total, times) | our server | yes | caregiver and doctor reports, restore |
| Reminder times and done marks (never the reminder text) | our server | yes | caregiver reports, restore |
| Consent decisions | our server | yes | legal record |
| Push token | our server | yes | alerts to caretakers and doctors |
| Typed chat messages (only with the separate companion consent) | passed through our server to an AI service, **not stored by us** | yes | the chat reply |
| Photos, family contacts, date of birth, caregiver PIN | **stay on the phone** (encrypted) | n/a | n/a |

No advertising, no analytics SDK, no tracking, no data sold or shared for marketing.

Suggested form answers (confirm with counsel):

- **Apple "App Privacy"**: Contact Info (name, phone) and User Content (customer support/other, for chat) and Health & Fitness / Other Data (game and reminder activity: choose the category your counsel prefers, since this is health-adjacent) as *Data Linked to You*, purpose *App Functionality*; "Data Used to Track You": none.
- **Google Play "Data safety"**: collects Personal info (name, phone), App activity (in-app interactions), Health info or Other (as above); encrypted in transit: yes; user can request deletion: yes (in-app erase, which also erases on the server); not shared with third parties except the AI service when the companion consent is on.
- **Account deletion**: both stores require an in-app route. It exists (Profile, Privacy and permissions, Erase). Add a web page with the same steps for the Play listing.
- **Privacy policy URL**: required by both. Base it on the consent text and `SECURITY.md`; have counsel write it (DPDP notice, grievance officer, cross-border statement for the companion, retention).

## 3. Store listing (draft)

**Name:** Smriti Sathi: Memory Companion

**Short description (80 characters):** Gentle memory games, reminders and family support for older adults.

**Full description (English):**
Smriti Sathi is a simple, calm app with memory games, daily reminders and an easy way to
call family. Games adjust to a comfortable level, instructions can be spoken aloud, and the
app works without internet. Family caregivers and doctors can, only with the person's
permission, see how the app is being used and get a gentle alert if something changes.

Important: Smriti Sathi is for memory exercise and reminders. It does not diagnose, treat
or monitor any medical condition and is not a substitute for a doctor.

Available in English, Hindi, Bengali and Assamese.

**हिन्दी (संक्षेप):** स्मृति साथी: याददाश्त के सरल खेल, समय पर याद दिलाना और परिवार को एक टैप में फ़ोन। यह कोई चिकित्सा उपकरण नहीं है और डॉक्टर की सलाह का विकल्प नहीं है।

**Category:** Health & Fitness (check that this does not trigger medical-device rules in
your target countries; if in doubt choose Lifestyle). **Age rating:** 4+/Everyone; the
chat feature is off until consent is given. **Support contact, website, privacy URL:** yours.

**Screenshots to prepare:** Home, a game, Reminders, Progress, caregiver dashboard, Talk to
Smriti, language picker. Take them in English and Hindi.

## 4. Before the first public release

Blocking:
1. Independent security test (VAPT) and fixes. See `SECURITY.md`.
2. Real SMS provider with DLT registration; hosting in an Indian region; logs kept 180 days.
3. Legal review: consent notice, privacy policy, guardian consent, retention, grievance officer, cross-border position for the AI companion.
4. Clinical review of wording ("not a medical device", alerts, emergency replies) and of the emergency word lists.
5. Native-speaker review of the Hindi, Bengali and Assamese texts.
6. Named incident lead, contact list and one drill (`INCIDENT_RESPONSE.md`).
7. Release signing keys created and backed up (Android key store, Apple certificates).
8. A pilot with a small number of real households before wider release, with a plan to collect feedback and consented transcripts of the chat if you want to review its safety.

If using the optional features:
- Push: Firebase project, `google-services.json`, the Firebase plugin, a token source in `main.dart` (see `lib/services/push_service.dart`), and a live test of `FcmPush`.
- AI chat: vendor agreement and retention settings, cost measurement, `SMRITI_COMPANION_*` settings.

## 5. Updating

- Database changes: add an Alembic migration; deploy with `alembic upgrade head` before the new server starts (`DEPLOYMENT.md`).
- App changes that alter the local database: bump `AppDatabase.schemaVersion`, add an upgrade step and a test (see `test/app_database_test.dart`).
- Anything that adds personal data needs a consent purpose, a `requireConsent` gate, export, erase, and an audit entry with no health content.
