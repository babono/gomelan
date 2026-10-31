#!/usr/bin/env bash
# Fails when UI text is missing a translation.
#
# Two ways text slips through: a literal the compiler extracted that never
# reached Localizable.xcstrings (only Xcode's own build syncs the catalog;
# `xcodebuild` on the command line does not), and a catalog entry with no
# Indonesian. Run after a build, so the extracted .stringsdata is fresh.
set -euo pipefail

python3 - "$@" <<'PY'
import glob, json, os, sys

langs = ["id"]
objs = glob.glob(os.path.expanduser(
    "~/Library/Developer/Xcode/DerivedData/Kotek-*/Build/Intermediates.noindex/Kotek.build/*/Kotek.build/Objects-normal/*"))
if not objs:
    sys.exit("check-strings: no build products found — build first")
newest = max(objs, key=os.path.getmtime)
extracted = {}
for f in glob.glob(os.path.join(newest, "*.stringsdata")):
    data = json.load(open(f))
    for e in data["tables"].get("Localizable", []):
        extracted.setdefault(e["key"], os.path.basename(data["source"]))

problems = []
for catalog in ["Kotek/Localizable.xcstrings", "Kotek/App/InfoPlist.xcstrings"]:
    strings = json.load(open(catalog))["strings"]
    if catalog.endswith("Localizable.xcstrings"):
        for key, src in sorted(extracted.items()):
            if key and key not in strings:
                problems.append(f"not in catalog (build in Xcode to add it): {key!r} — {src}")
    for key, entry in sorted(strings.items()):
        if not key or not entry.get("shouldTranslate", True):
            continue
        have = entry.get("localizations", {})
        for lang in langs:
            if lang not in have:
                problems.append(f"no {lang} translation: {key!r} — {os.path.basename(catalog)}")

if problems:
    print("\n".join(problems))
    sys.exit(f"check-strings: {len(problems)} string(s) need attention")
print("check-strings: every string is translated")
PY
