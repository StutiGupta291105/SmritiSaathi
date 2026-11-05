# Real-phone test checklist (offline and reminders)

The automated tests use a real server and the real app code, but cannot toggle a phone's
radio or kill its battery. Run this once on a physical Android phone with the APK from the
`build-apk.yml` workflow. Tick each line; note the phone model and Android version.

## Patient, offline
1. Sign in online once. Turn on **Airplane mode**.
2. Open the app: the yellow "You are offline" bar appears; Home, Games, Reminders, Profile open.
3. Play a game and tick a medicine. The bar's "waiting to send" count rises.
4. Close the app from recents, reopen (still offline): progress and ticks are still there.
5. Add a reminder for 3 minutes ahead: you get the 30-minute heads-up (use a 31-minute one)
   and the at-time alert with the app closed and the phone locked.
6. Turn on **Battery saver**; repeat step 5. If alerts are late, allow "Unrestricted" battery for the app.
7. Turn Airplane mode off. Within about a minute the count goes to 0 and a caregiver sees the game.

## Chat, offline
8. In a conversation, send text, a photo and a voice note while offline: each shows "Waiting to send".
9. Close and reopen the app, go online: all three arrive once, in order. A 12 MP gallery photo arrives (it is shrunk).

## Caregiver or doctor
10. Open the dashboard online, then go offline: "Showing saved information from <time>".
11. Reply offline: it waits and goes out when online.
12. Have the patient withdraw sharing, keep the caregiver phone offline, then online: the saved copy disappears.

## Server waking
13. Leave the test server idle for 20 minutes (or disable `keep-warm.yml`), open the app: the
    "Connecting... server was resting" bar shows, then clears with no error.

## Push with the app closed (needs Firebase set up)
14. Swipe the caregiver app away; have the patient trigger an alert; a notification arrives.
