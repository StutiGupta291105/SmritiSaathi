# Translation review sheets

One CSV per language. Smriti Sathi is used by older adults, so wording matters most for
emergency, safety, consent and medicine texts (priority 1; they are listed first).

## For a native-speaker reviewer
1. Open `<language>.csv` in Excel or Google Sheets (UTF-8).
2. Read `english` and `current`. If `current` is wrong, unnatural, too formal or could
   confuse an older person, type the better text in `corrected`. Leave it blank if fine.
3. Keep `{a}`, `{b}`, `{w}`, `{d}`, `{m}`, `{y}`, `{t}` exactly as they are: the app fills
   them in with names, numbers and times.
4. Use short, calm, respectful sentences. Never wording that sounds like a diagnosis.
5. Send the file back.

## For the project team
```
python3 tools/translation_review.py import ta          # applies translation_review/ta.csv
python3 tools/translation_review.py import ta --mark-reviewed   # also removes the "draft" label
flutter test                                           # parity tests check every key
```
Re-export with `python3 tools/translation_review.py export` after strings change.
Only mark a language reviewed after a native speaker has gone through at least the
priority 1 rows.
