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

## Caregiver and doctor screens (look and feel on a real phone)
Use a caregiver and a doctor account linked to the same test patient. Check each on a small
phone (about 5 inch) and, if you can, with the system font size set to Large.
15. Caregiver Home: the garden sky matches the time of day; "x of y active today" is right; the
    bell shows a count and opens Alerts; the timeline lists today's routines with a glowing "now".
16. Caregiver Consult: Patients shows each patient; Doctors shows the doctor of those patients,
    and nobody else. Send a message each way; the unread badge appears and clears.
17. Caregiver patient screen: the four buttons (Messages, Doctor, Reports, Routine) fit on one
    line each; Notes tab: add a note, see the doctor's note, delete only your own.
18. Add a routine with a quick template (e.g. Drink a glass of water): the time and title fill in.
19. Doctor: Consult has Patients (own patients first, then questions from other patients) and
    Caregivers; open an opinion request and reply. Prescribe a medicine twice a day: the patient's
    phone shows two reminders after it syncs.
20. Rotate the phone and use the keyboard in the note field: nothing is hidden behind it.
