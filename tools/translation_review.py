#!/usr/bin/env python3
"""Review workflow for the app's translations.

Every language except English is a machine-assisted draft. This tool turns each one
into a spreadsheet a native speaker can correct, then puts the corrections back.

  python3 tools/translation_review.py export            # one CSV per language
  python3 tools/translation_review.py export ta hi      # only some languages
  python3 tools/translation_review.py import ta         # apply translation_review/ta.csv
  python3 tools/translation_review.py import ta --mark-reviewed   # drop the "draft" label

CSV columns: priority, section, key, english, current, corrected, notes.
Reviewers only fill `corrected` (and `notes`); a blank means "current is fine".
Priority 1 rows (emergency, safety, consent, medicine) should be reviewed first.
Open the CSV in Excel or Google Sheets as UTF-8. On import, a correction is refused if
it drops or adds a {placeholder} that the English text has. After importing, run
`flutter test` (the language tests check every key and placeholder)."""
import argparse
import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LINE = re.compile(r'^(\s*)(["\'])(.+?)\2(\s*:\s*)(["\'])(.*)\5(,\s*)$')
PH = re.compile(r"\{[a-z]+\}")
PRIORITY1 = re.compile(r"emerg|sos|safe|112|consent|medicine|prescri|chatAi|dementia|diagnos|notAdoctor|911", re.I)


def unesc(v: str) -> str:
    return (v.replace(r"\n", "\n").replace(r"\"", '"').replace(r"\'", "'")
             .replace(r"\$", "$").replace("\\\\", "\\"))


def esc(v: str) -> str:
    return (v.replace("\\", "\\\\").replace('"', r"\"").replace("$", r"\$")
             .replace("\n", r"\n"))


def sections(root: Path):
    """{lang: [(file, section, first_line, last_line)]} (0-based, inclusive)."""
    out: dict[str, list] = {}
    lang_dir = root / "lib/core/lang"
    for f in sorted(lang_dir.glob("*.dart")):
        if f.name.startswith("_"):
            continue
        lines = f.read_text(encoding="utf-8").splitlines()
        for name in ("strings", "labels"):
            start = next((i for i, l in enumerate(lines) if l.strip() == name + ": {"), None)
            if start is None:
                continue
            end = next(i for i in range(start + 1, len(lines)) if lines[i].strip() == "},")
            out.setdefault(f.stem, []).append((f, name, start + 1, end - 1))
    for code, fname, opener in (("bn", "strings_bn.dart", "const Map<String, String> kStringsBn = {"),
                                ("as", "strings_as.dart", "const Map<String, String> kStringsAs = {")):
        f = root / "lib/core" / fname
        lines = f.read_text(encoding="utf-8").splitlines()
        start = next(i for i, l in enumerate(lines) if l.startswith("const Map<String, String>"))
        end = next(i for i in range(start + 1, len(lines)) if lines[i].strip() == "};")
        out[code] = [(f, "strings", start + 1, end - 1)]
    f = root / "lib/core/strings.dart"
    lines = f.read_text(encoding="utf-8").splitlines()
    for code in ("en", "hi"):
        start = next(i for i, l in enumerate(lines) if l.strip() == f"'{code}': {{")
        end = next(i for i in range(start + 1, len(lines)) if lines[i] == "  },")
        out[code] = [(f, "strings", start + 1, end - 1)]
    return out


def read_rows(spec):
    f, _name, a, b = spec
    rows = {}
    for l in f.read_text(encoding="utf-8").splitlines()[a:b + 1]:
        m = LINE.match(l)
        if m:
            rows[unesc(m.group(3))] = unesc(m.group(6))
    return rows


def cmd_export(root: Path, langs, outdir: Path):
    secs = sections(root)
    en = read_rows(secs["en"][0])
    outdir.mkdir(exist_ok=True)
    for code in langs or [c for c in sorted(secs) if c != "en"]:
        if code == "en" or code not in secs:
            continue
        rows = []
        for spec in secs[code]:
            for key, cur in read_rows(spec).items():
                source = en.get(key, key) if spec[1] == "strings" else key
                pr = 1 if PRIORITY1.search(key) else (3 if spec[1] == "labels" else 2)
                rows.append((pr, spec[1], key, source, cur))
        rows.sort(key=lambda r: (r[0], r[1], r[2]))
        with open(outdir / f"{code}.csv", "w", encoding="utf-8-sig", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["priority", "section", "key", "english", "current", "corrected", "notes"])
            for r in rows:
                w.writerow([*r, "", ""])
        print(f"{code}: {len(rows)} rows -> {outdir / (code + '.csv')}")


def cmd_import(root: Path, code: str, outdir: Path, mark: bool):
    secs = sections(root)
    if code not in secs or code == "en":
        sys.exit(f"unknown language {code}")
    en = read_rows(secs["en"][0])
    corrections: dict[tuple[str, str], str] = {}
    with open(outdir / f"{code}.csv", encoding="utf-8-sig", newline="") as fh:
        for r in csv.DictReader(fh):
            new = (r.get("corrected") or "").strip()
            if new:
                corrections[(r["section"], r["key"])] = new
    applied = refused = 0
    for spec in secs[code]:
        f, name, a, b = spec
        text = f.read_text(encoding="utf-8").splitlines()
        for i in range(a, b + 1):
            m = LINE.match(text[i])
            if not m:
                continue
            key = unesc(m.group(3))
            new = corrections.pop((name, key), None)
            if new is None:
                continue
            src = en.get(key, key) if name == "strings" else key
            if name == "strings" and sorted(PH.findall(src)) != sorted(PH.findall(new)):
                print(f"REFUSED {key}: placeholders {PH.findall(src)} must match {PH.findall(new)}")
                refused += 1
                continue
            q = m.group(2)
            body = new.replace("\\", "\\\\").replace("\n", r"\n").replace("$", r"\$")
            body = body.replace(q, "\\" + q)
            text[i] = f"{m.group(1)}{q}{m.group(3)}{q}{m.group(4)}{q}{body}{q}{m.group(7)}"
            applied += 1
        f.write_text("\n".join(text) + "\n", encoding="utf-8")
    for (name, key) in corrections:
        print(f"IGNORED {name}/{key}: not found")
    print(f"{code}: {applied} corrections applied, {refused} refused")
    if mark and not refused:
        p = root / "lib/core/languages.dart"
        s = p.read_text(encoding="utf-8")
        i = s.index("kDraftLanguages = {")
        j = s.index("};", i)
        block = re.sub(r"'%s',\s*" % re.escape(code), "", s[i:j])
        s2 = s[:i] + block + s[j:]
        p.write_text(s2, encoding="utf-8")
        print(f"{code}: no longer labelled a draft (check kDraftLanguages in languages.dart)")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["export", "import"])
    ap.add_argument("langs", nargs="*")
    ap.add_argument("--root", default=str(ROOT))
    ap.add_argument("--dir", default=None, help="where the CSVs are (default: translation_review/)")
    ap.add_argument("--mark-reviewed", action="store_true")
    a = ap.parse_args()
    root = Path(a.root)
    outdir = Path(a.dir) if a.dir else root / "translation_review"
    if a.cmd == "export":
        cmd_export(root, a.langs, outdir)
    else:
        if len(a.langs) != 1:
            sys.exit("import takes exactly one language code")
        cmd_import(root, a.langs[0], outdir, a.mark_reviewed)
