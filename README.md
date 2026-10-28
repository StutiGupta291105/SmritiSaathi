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

UI notes from the mockups: Progress shows engagement only (games played, day
streak, level, weekly activity) and never a "cognitive score" or health label.
Assamese and Bengali need translated strings before they appear in Settings.
The caregiver, healthcare-worker and admin apps and the "Talk to AI" screen
are not started; they need the backend (auth, roles) first.

None of this has been compiled or run yet.

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
