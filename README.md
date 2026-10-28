# SmritiAssist

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

## What exists so far

| Area | File | Status |
|---|---|---|
| Adaptive difficulty (staircase, caregiver band, baseline suggestions) | `lib/core/adaptive_engine.dart` | written, tests in `test/` |
| Encrypted offline DB, consent log, audit log, sync queue, DPDP access/erasure | `lib/data/app_database.dart` | written |
| Caregiver onboarding: consent per purpose + starting level | `lib/features/onboarding/` | written |
| Game 1: pair matching, level-scaled | `lib/features/games/memory_match_game.dart` | written |
| English / Hindi strings | `lib/core/strings.dart` | written (migrate to ARB later) |

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
| Withdrawal of consent | `consents` keeps newest decision per purpose (`hasConsent`); in-app withdrawal UI still to build |
| Access and erasure | `exportPatient`, `erasePatient` (UI still to build) |
| Data minimisation | Only name, language, level, session summaries stored; no contacts or location |
| Encryption at rest | SQLCipher, key in Keystore/Keychain |
| Audit trail and 180-day log retention | `audit_log` table; retention job and India-hosted log store still to build |
| Breach / incident reporting (6 h) | Process document still to write |
| VAPT, OWASP MASVS | Planned before any real deployment |
| Encryption in transit, auth, roles | Pending (backend not started) |

Check the current DPDP Rules text and commencement dates before citing them.

## Next steps

1. Run the setup above and confirm it compiles; fix anything it flags.
2. Reminders (local notifications for medicine, water, appointments).
3. Games 2 and 3: attention (find the target) and routine sequencing.
4. Sync service and backend (auth, roles, consent log mirror).
5. Caregiver dashboard (web), plus the baseline-suggestion banner using `suggestBaseline`.
6. Voice prompts (text-to-speech first).
