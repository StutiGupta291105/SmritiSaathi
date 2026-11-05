# Languages

Smriti Sathi shows English plus the 22 languages of the Eighth Schedule of the
Constitution of India. The same list drives the app, the spoken voice, the
offline "Talk to Smriti" helper and the server.

| Code | Language | Script | Direction |
|------|----------|--------|-----------|
| en | English | Latin | LTR |
| hi | Hindi | Devanagari | LTR |
| bn | Bengali | Bengali | LTR |
| te | Telugu | Telugu | LTR |
| mr | Marathi | Devanagari | LTR |
| ta | Tamil | Tamil | LTR |
| ur | Urdu | Perso-Arabic | **RTL** |
| gu | Gujarati | Gujarati | LTR |
| kn | Kannada | Kannada | LTR |
| ml | Malayalam | Malayalam | LTR |
| or | Odia | Odia | LTR |
| pa | Punjabi | Gurmukhi | LTR |
| as | Assamese | Bengali-Assamese | LTR |
| mai | Maithili | Devanagari | LTR |
| sat | Santali | Ol Chiki | LTR |
| ks | Kashmiri | Perso-Arabic | **RTL** |
| ne | Nepali | Devanagari | LTR |
| kok | Konkani | Devanagari | LTR |
| mni | Manipuri (Meitei) | Meetei Mayek | LTR |
| brx | Bodo | Devanagari | LTR |
| doi | Dogri | Devanagari | LTR |
| sd | Sindhi | Perso-Arabic | **RTL** |
| sa | Sanskrit | Devanagari | LTR |

## Every language is a draft

Only English and Hindi were written with the app. **All other texts are drafts
written by an AI model and have not been reviewed by native speakers.** Quality
is uneven: the large languages (Telugu, Marathi, Tamil, Urdu, Gujarati, Kannada,
Malayalam, Punjabi, Odia, Nepali, Bengali, Assamese) are better than Maithili,
Konkani, Sanskrit and Sindhi, which are better than **Bodo, Dogri, Kashmiri,
Santali and Manipuri, which are low confidence**. The picker labels each draft.

Before real use a native speaker must check, in this order:

1. `safety_data.py`: the emergency words and the emergency reply. A miss here is
   the most serious error.
2. The consent texts (`consentTitle`, `consentIntro`, `purpose*`, `perm*`,
   `notAMedicalDevice`, `chatOnlineAsk`). DPDP requires the notice to be
   understood by the person giving consent.
3. Medicine and reminder wording (`notif_*`, `kind_*`, `alert_*`).
4. Everything else.

## What is in a language

- `lib/core/lang/<code>.dart`: one `LangData`: all UI texts (same keys as
  English), labels for the game pictures and routines, weekday and month names,
  the "today is" sentence and three kind sentences.
- `lib/core/languages.dart`: name in its own script, English name, voice locales,
  right-to-left set, draft set.
- `backend/app/safety_data.py`: emergency words, emergency reply and the
  "I am not sure" reply. `python tools/gen_safety.py` writes the app's offline
  copy (`lib/core/safety_data.dart`); a test fails if they drift apart.
- `python tools/gen_lang_registry.py` rewrites `lib/core/lang/_all.dart`.

To add or fix a language edit its file, run the two generators, then
`flutter test` (key and placeholder parity, layout at five screen sizes for
`ta`, `ml`, `ur` and `sat`) and `pytest` in `backend/`.

## Things to know

- **Fonts.** The app uses the phone's own fonts for these scripts. Almost every
  Android phone has Indic and Arabic scripts, but **Ol Chiki (Santali) and Meetei
  Mayek (Manipuri) are missing on many phones and show as empty boxes.** The
  language picker therefore always shows the English name under each language,
  so a person can get back to a language they can read.
- **Voice.** Spoken instructions need a text-to-speech voice for the language.
  Where none is installed the app stays silent and the written text is the
  instruction. Languages written in Devanagari fall back to the Hindi voice,
  Perso-Arabic ones to Urdu. Odia, Santali and Manipuri usually have no voice.
- **Right to left.** Urdu, Kashmiri and Sindhi mirror the layout. Arrow icons
  are not yet mirrored everywhere.
- **Numbers** are shown with ordinary digits (0-9) in every language so they
  match the phone keypad, the OTP and the emergency number 112.
- **Emergency words** are matched on the phone and on the server, in the
  person's language and in English. Replies for the least certain languages
  repeat "please call 112" in English.
