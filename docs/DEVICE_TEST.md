# Real-phone test checklist (offline and reminders)

> **Permissions test:** on a freshly installed app, the splash goes straight to Get Started / Log in with no prompt. Create an account: the Permissions screen appears once; Allow shows the phone's own dialogs one after another (microphone, location, notifications, then the exact-alarm settings page). After that no screen or feature shows another prompt; if one was refused, voice notes and "Are You Lost?" show a message with a Settings button.

> **"App not installed"?** Android refuses an update that is signed with a different key than
> the installed app. Test builds before the fixed test key (`.github/keys/`) each had a random key.
> Uninstall Smriti Sathi once (account data stays on the server; anything saved only on the phone
> is lost), then install the new APK. After that, every new test APK installs over the old one.

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

## Live location (two phones: patient and caregiver; a third for a family member's SMS)
21. Patient: add a family member and tick **Include in live location** (or tap the pin icon on
    the family row). The patient Home shows **Are You Lost? Tell Your Loved Ones** at the very top.
22. **One tap** on the card: it starts at once, with no questions (the first time, allow
    location). The caregiver gets the chat message by itself. The messaging app then opens with
    one message ready for the ticked family members: press send. A message at the bottom says who
    it went to and has **Stop sharing**. The card turns green. The slider icon on the card opens
    the chooser (who, how long: just now / 30 min / 1 / 2 hours).
23. Caregiver phone: a chat message with **Open map** arrives (push too), and the patient screen
    shows a green **Live location** card with "x min ago" that moves as the patient walks.
24. Family phone: the SMS link opens a map page that refreshes by itself. Press **Stop sharing**
    on the patient phone: the page now says the live location has ended.
25. Lock the patient phone for a few minutes while walking: sharing carries on (a notification
    "Sharing your location" is shown), and the caregiver's card still updates. If it does not on
    Oppo/Realme/Xiaomi/Vivo, set Battery to Unrestricted for the app.
26. Switch the patient phone to Airplane mode and share: it falls back to a one-time map link and
    the chat message is queued; it goes out when the phone is online again.

## Talk to Smriti: the microphone
27. Open Talk to Smriti and tap the big microphone (or the small one in the text box, which also
    works with the keyboard open). It turns red and says "Listening… speak now"; the words appear
    in the box as you speak and are sent by themselves when you stop. Tap again to stop early.
28. It listens in the app's language (Hindi app: speak Hindi). If the microphone was refused after
    sign-up it says so with a Settings button; on a phone with no speech service it says to use the
    keyboard's own microphone. Android needs the Google app / speech services installed; for offline
    use download the language in Settings > Google > Speech.

## When reminders or alerts do not arrive
1. Settings > **Notification check** lists what is wrong in plain words (blocked notifications,
   exact alarms off, reminders not allowed, nothing scheduled, no push in this build).
2. Tap **Fix permissions**, then **Show a test alert now** (proves notifications can appear) and
   **Schedule a test alert in 1 minute** (lock the phone; proves scheduled alerts work, which is
   what real reminders use).
3. On Oppo, Realme, OnePlus, Xiaomi and Vivo phones also allow **Auto-start** and set Battery to
   **Unrestricted** for the app, otherwise the phone kills it.
4. Open `https://<your-server>/healthz`: `"push": true` means the server can send real push; if it
   says false, set `SMRITI_PUSH_PROVIDER=fcm` and the two FCM variables (docs/DEPLOYMENT.md).
5. The release APK needs the keep-rules in `.github/scripts/proguard-rules.pro` (applied by the
   build); without them scheduling fails in the installed app even though it works in debug.
6. No sound? Notification check shows "Alert sound". Reminders use their own channel
   (`reminder_alerts`, urgent, vibrating, alarm-style) and chat push uses `messages`; both are
   created at start-up. If the phone has set that channel to silent, or Do Not Disturb is on, tap
   **Open phone settings** > Notifications > Reminder alerts and set Sound on / Importance Urgent.
