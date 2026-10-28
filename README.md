# Smriti Sathi (Better Memory. Brighter Days.)

Offline-first mobile app (Android + iOS, Flutter) offering memory and attention
games, routine support and reminders for elderly users, with a caregiver view.
**It does not diagnose or treat any condition.** All in-app and paper wording
should say "cognitive engagement and performance trends", never "cognitive
score" or "detection".

## First-time setup (on your machine)

The project files were written without a Flutter SDK available, so generate the
platform folders and fetch packages once:

```bash
cd smriti_assist
flutter create . --project-name smriti_assist --platforms android,ios
flutter pub get
flutter test          # adaptive engine unit tests
flutter run
```

`flutter create .` keeps the existing `lib/`, `test/` and `pubspec.yaml`. If
`pub get` reports a version conflict, loosen the caret versions in `pubspec.yaml`.
Android needs `minSdkVersion 21` or higher for `flutter_secure_storage` and
`sqflite_sqlcipher` (set in `android/app/build.gradle`).

Platform hardening to apply after `flutter create` (security baseline):

- `AndroidManifest.xml`: set `android:allowBackup="false"` and
  `android:usesCleartextTraffic="false"` on `<application>`; add
  `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM` and `RECEIVE_BOOT_COMPLETED`
  permissions and the `flutter_local_notifications` receivers (see that
  package's setup guide) so reminders survive a reboot.
- Enable core library desugaring in `android/app/build.gradle`
  (`flutter_local_notifications` requires it).
- iOS: leave App Transport Security at its default (HTTPS only).

## What exists so far

| Area | File | Status |
|---|---|---|
| Adaptive difficulty (staircase, caregiver band, baseline suggestions) | `lib/core/adaptive_engine.dart` | written, tests in `test/` |
| Encrypted offline DB, consent log, audit log, sync queue, DPDP access/erasure | `lib/data/app_database.dart` | written |
| Caregiver onboarding: consent per purpose + starting level | `lib/features/onboarding/` | written |
| Game 1: pair matching, level-scaled | `lib/features/games/memory_match_game.dart` | written |
| English / Hindi strings | `lib/core/strings.dart` | written (migrate to ARB later) |
| Reminders: medicine, water, activity, appointment (offline local notifications) | `lib/core/reminder_schedule.dart`, `lib/services/reminder_notifier.dart`, `lib/features/reminders/` | written, schedule tests in `test/` |
| Privacy screen: consent switches, access, erasure | `lib/features/privacy/` | written |
| Elderly app shell per the mockups: Home (greeting, today's tasks), Games, Reminders, Progress, Settings (English/Hindi) | `lib/features/shell/`, `lib/core/theme.dart`, `lib/core/progress.dart` | written, streak tests in `test/` |

| Game 2: "Find the target" (attention; grid 4-16 cells, look-alikes from level 4) | `lib/features/games/attention_game.dart`, `lib/core/attention_round.dart` | written, tests in `test/` |
| Game 3: "My day" (daily-routine recall; 3-7 steps of morning / tea / evening routines) | `lib/features/games/routine_game.dart`, `lib/core/routine_round.dart` | written, tests in `test/` |
| Spoken instructions (on-device text-to-speech, English and Hindi, per-person toggle) | `lib/services/voice.dart` | written |
| Culturally familiar content (objects, look-alikes, routines) | `lib/core/content.dart` | starter set; regional packs and caregiver-edited routines still to build |

Voice notes: speech uses the phone's own TTS engine and we send no text to any
service. Some Android engines fetch voices online, and Hindi may need a one-time
voice download; on-screen text is always shown too. Speech-to-text (voice input)
is not built yet. Routine orders are common defaults, so caregivers should be
able to edit them to match the person's day.

UI notes from the mockups: Progress shows engagement only (games played, day
streak, level, weekly activity) and never a "cognitive score" or health label.
Assamese and Bengali need translated strings before they appear in Settings.
The caregiver, healthcare-worker and admin apps and the "Talk to AI" screen
are not started; they need the backend (auth, roles) first.

Verification so far (Flutter 3.35.7, the version the APK workflow pins):
`flutter analyze` is clean and 48 unit tests pass, including `AppDatabase`
tests that run the real database code on desktop SQLite (consent gating, audit
hash chain, export, erasure, v1 to v2 upgrade). Not yet done: running the app
on a device or emulator, and widget tests of the screens.

## Sign-in and profile flow (patient)

1. **Login / create account**: role (patient, doctor, caretaker), mobile number,
   OTP. Creating a patient account asks name + number + OTP.
2. **Consent** (first login): notice and per-purpose consent, starting game level.
3. **Profile completion**, five steps, resumable: about you (photo, date of birth
   with automatic age, language), family members (name, phone, relationship,
   optional photo), care team (doctor and caregiver name + ID, saved as invites),
   daily routine (reminders), phone and location permissions.
4. **Dashboard**: Home (with tap-to-call family), Games, Reminders, Progress.

**Test-mode pieces that must be replaced before real use:**

- OTP is `DevOtpService`: no SMS is sent and the code is always `123456` (the
  login screen shows a banner). Swap in a real SMS OTP service behind `OtpService`.
- Doctor and caregiver invites are only *saved* (status `pending`). Delivering
  them, and the doctor/caregiver accepting, needs the backend. Doctor and
  caretaker logins currently reach a "coming soon" page.
- Doctor and caregiver IDs are not verified against any registry.
- "Phone" permission is requested as asked, but tap-to-call opens the dialer and
  does not need it; Google Play restricts `CALL_PHONE`, so consider dropping it.
  Location is only a permission for now: no location is collected.

iOS needs these `Info.plist` keys after `flutter create` (usage descriptions):
`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`,
`NSLocationWhenInUseUsageDescription`.

## Design decisions

- **Caregiver sets the starting level.** The engine moves at most one level
  either way (`DifficultyBand`). Across sessions it only *suggests* a baseline
  change; `AppDatabase.setBaseline` records who changed it and why.
- **Early cognitive intervention** is framed as regular supportive engagement
  plus caregiver alerts when engagement changes, not as screening.
- **Consent is per purpose** and recorded with who gave it (self or guardian)
  and the notice version. Gameplay storage is the only required purpose.

## Compliance map (DPDP Act and CERT-In)

| Requirement | Where it lives |
|---|---|
| Notice and purpose-wise consent, guardian consent | Onboarding screen, `consents` table |
| Withdrawal of consent | `withdrawConsent`; `Privacy and permissions` screen. Withdrawal takes effect at once |
| Consent enforced, not just recorded | `requireConsent` gates session writes (`gameplay`), reminders (`reminders`) and sync (`sync`) inside `AppDatabase` |
| Access and erasure | `exportPatient`, `erasePatient`; both on the Privacy screen, both audited |
| Third-party data (family contacts) | Own purpose `family_contacts`; hidden when withdrawn; included in export and erase |
| Sharing with doctor / caregiver | Purposes `doctor_share`, `caregiver_share`; invites become `revoked` on withdrawal; nothing shared before the backend and their acceptance |
| Photos | Stored inside the encrypted database; the picker's temporary file is deleted; export lists size only |
| Login | OTP with 5-try lockout; account existence only revealed after OTP; session id in Keystore/Keychain; logout cancels reminders |
| Data minimisation | Only name, language, level, reminders, session summaries stored; no contacts or location. Lock-screen reminder text is generic (no medicine names); audit log never holds reminder text |
| Encryption at rest | SQLCipher, key in Keystore/Keychain |
| Audit trail and 180-day log retention | SHA-256 hash-chained `audit_log` (`verifyAuditChain`); `purgeAuditOlderThan` never purges under 180 days and only entries already shipped. India-hosted log store still to build |
| Breach / incident reporting (6 h) | Process document still to write |
| VAPT, OWASP MASVS | Planned before any real deployment |
| Encryption in transit, auth, roles | Pending (backend not started) |

Check the current DPDP Rules text and commencement dates before citing them.

## Next steps

1. Run the setup above and confirm it compiles; fix anything it flags.
2. Compliance rule for every new feature: new personal data needs a consent
   purpose, a `requireConsent` gate, inclusion in `exportPatient` and
   `erasePatient`, and an audit entry that holds no health content.
3. Games 2 and 3: attention (find the target) and routine sequencing.
4. Sync service and backend (auth, roles, consent log mirror).
5. Caregiver dashboard (web), plus the baseline-suggestion banner using `suggestBaseline`.
6. Voice prompts (text-to-speech first).
