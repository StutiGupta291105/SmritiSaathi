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
`flutter analyze` is clean and 102 unit tests pass, including `AppDatabase`
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

## Phase 2: caregiver dashboard, alerts, learned difficulty

**Caregiver area** (Settings, behind a 4-6 digit PIN created on first use): an
overview (games in the last 7 days, streak, last played, correct answers by
game), alerts, the starting-level control, shortcuts to edit reminders and the
daily routine, and the family and care team. It appears only while the
`caregiver_share` purpose is consented. The PIN is stored salted and hashed,
locks for 15 minutes after 5 wrong tries, and every outcome is audited. It is
an access control on a phone the patient also holds, not strong authentication,
and it cannot be recovered (forgetting it means erase and set up again).

**Learned difficulty** (`lib/core/ability_model.dart`): a one-parameter logistic
model, P(correct | level) = sigmoid(1.2 x (ability - level)), fitted on the
person's own per-level results (the last 40 sessions of each game) by MAP
estimation. The prior is centred so that with no data the recommendation is
exactly the caregiver's baseline. Each game starts at the level whose predicted
success is closest to 75 percent, clamped to the caregiver's band (baseline
plus or minus one). The within-session staircase still runs on top. The
dashboard shows the level each game will start at and how many answers it is
based on. Sessions saved before this version have no per-level tallies and are
ignored by the model.

**Alerts** (`lib/core/engagement_alerts.dart`), worded about use of the app,
never health. Shown in the dashboard, and as a red count on the Caregiver area
entry in Profile (without opening the PIN screen):

| Alert | Rule |
|---|---|
| Not played | at least 5 sessions so far and none for 3 or more days |
| Fewer sessions | last 7 days have half or fewer than the 7 days before (which had at least 4) |
| Fewer correct answers | last 3 sessions average 20 or more points below the 5 before (needs 8 sessions) |
| Medicine not marked done | a medicine reminder from today, due 2 or more hours ago, has no done mark |
| Few reminders marked done | under half of the last 7 days' reminders marked done (needs at least 6 due) |
| Raise / lower baseline | last 3 sessions all ended at the top / bottom of the band; "Review" opens the level dialog pre-set to the suggestion |

**Reminder completion:** the patient ticks today's tasks on Home (`reminder_log`:
reminder id and day only, covered by the `reminders` purpose, included in export
and erase). "Not marked done" is all this can say, since someone may have taken
their medicine without tapping.

**Reports:** 7 Days / 30 Days / 3 Months (`lib/core/reporting.dart`) for games,
chart (daily bars, weekly for 3 months) and correct answers by game, plus a
"Copy summary to share" button that puts a plain-text summary (no phone numbers)
on the clipboard for the caregiver to paste to a doctor or family.

### Phase 2 status

| Planned | Status |
|---|---|
| Caregiver dashboard (engagement, per-game results, reminders, family and care team) | done |
| Alerts when engagement changes | done, also surfaced as a badge |
| Reminder / medicine completion tracking and alerts | done |
| Reports over 7 / 30 / 90 days and a shareable summary | done |
| Baseline suggestion banner with one-tap review | done |
| On-device adaptive model | done, lighter than first planned: a per-game logistic ability model rather than a contextual bandit; it uses level history only, not time of day or other context |
| Caregiver on their own phone: live dashboard | done in Phase 3 (pull to refresh); push notifications not built |
| Healthcare-worker dashboard, patient list | done in Phase 3 (read-only report view); visit management not built |
| Doctor prescribing and updating a condition | out of scope for now: needs the backend, clinical review and regulatory decisions |


## Phase 3: backend and connected app

The server lives in `backend/` (FastAPI, PostgreSQL in production, India region;
see `docs/DEPLOYMENT.md`, `docs/SECURITY.md`, `docs/INCIDENT_RESPONSE.md`). The
app talks to it only when built with an API address:

    flutter build apk --release --dart-define=API_BASE_URL=https://your-api

The APK workflow reads that from the repository variable `API_BASE_URL`. With no
address the app stays the offline test build (fixed code 123456, no server).

| Item | Status |
|---|---|
| Real OTP login through the server, roles, rotating tokens | done (needs an SMS provider and DLT registration to send real SMS) |
| Invites reach doctors and caretakers by phone number; they accept or decline | done |
| Consent decisions mirrored to the server, including withdrawals | done |
| Game results and reminder timing synced, only with the matching consent; reminder text never leaves the phone | done |
| Caretaker and doctor see a shared report only while consent is on and the link accepted | done |
| Erase removes server data first (needs internet) | done |
| India-hosted log store, incident process, security review documents | written; hosting, named incident lead and external testing are for you to arrange |
| Not built yet | push notifications, restoring a patient on a new phone from the server, doctor registry verification, database migrations tool, caretaker changing the starting level from the app after first sync |

## Look and feel

Follows the second design sheet: teal-green brand (`#1B7F63`, headings
`#15503F`, action buttons `#2FA864`) on a warm cream background, white rounded
cards with a soft shadow, pastel tiles with a stronger icon colour of the same
hue, and Poppins lettering. The font is bundled in `assets/fonts` (SIL Open Font
License, see `OFL.txt`), so it works offline. Colours live in
`lib/core/theme.dart`, shared pieces (cards, pill tabs, icon badges, brand mark,
painted scenic header) in `lib/core/ui.dart`.

Screens built to the sheet: welcome (Get Started / Login / language), login and
create account, Home (Today's Goal card, four tiles, today's tasks), Games list,
game screens (title and subtitle, Time / Finish / Score footer, purple leaf-back
cards), Reminders (Today / Upcoming / All), My Progress (star level, XP,
games played, best streak, achievements, weekly chart), Profile (language,
spoken instructions, caregiver area, privacy, log out), caregiver dashboard.

Logo, icon and splash: the logo (elderly woman with app icons in her mind,
held by green hands) lives in `assets/images`. `logo.png` is used in the app,
`logo_foreground.png` and `logo_icon.png` feed the Android launcher icon, which
the APK workflow generates with `dart run flutter_launcher_icons` (after
`flutter create`). For iOS set `ios: true` in the `flutter_launcher_icons`
section of `pubspec.yaml` and run it locally. The source image was only about
190 px across, so a higher-resolution original would make the icon sharper.
The splash screen (`lib/features/splash`) shows while the database opens.

Deliberately different from the sheet:

- No "Cognitive Score" or "Cognitive Health" labels. Progress counts playing
  (XP, star level, achievements) and says so on screen.
- No "Talk to Smriti" AI chat: an AI conversation for people with dementia
  needs its own safety and consent decision.
- The painted illustration of the couple is replaced by a simple drawn village
  scene. Replace `SceneHeader` with real artwork when available.
- Only English and Hindi are offered; Assamese and Bengali need translations.
- Healthcare-worker and admin apps are not built (they need the backend).

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
| Encryption in transit, auth, roles | Built in `backend/` (HTTPS enforced by the app, hashed phone numbers, rotating tokens); needs deployment and external testing |

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
