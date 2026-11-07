"""Brings the app's text over from the Android app, so both say the same thing.

Reads res/values/strings.xml (English) and res/values-el/strings.xml (Greek)
of astiko-ktel-kastorias-app, from GitHub or from a local checkout, and writes
App/Resources/strings.json:

    {"en": {"key": "text", ...}, "el": {...},
     "plurals": {"en": {"key": {"one": "...", "other": "..."}}, "el": {...}},
     "arrays": {"en": {"key": ["...", ...]}, "el": {...}}}

The texts keep Android's placeholders (%1$s, %1$d, %2$02d); the app fills them
in itself (App/Sources/App/Strings.swift), so nothing is converted.

    python scripts/import_strings.py                               # from GitHub, main
    python scripts/import_strings.py --android ../astiko-ktel-kastorias-app
"""

import argparse
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "App" / "Resources" / "strings.json"
RAW = "https://raw.githubusercontent.com/Kastoria-Dev-Core/astiko-ktel-kastorias-app/main/app/src/main/res/{folder}/strings.xml"
FOLDERS = {"en": "values", "el": "values-el"}


def read(language: str, android: Path | None) -> str:
    folder = FOLDERS[language]
    if android:
        return (android / "app" / "src" / "main" / "res" / folder / "strings.xml").read_text(encoding="utf-8")
    with urllib.request.urlopen(RAW.format(folder=folder), timeout=30) as res:
        return res.read().decode("utf-8")


def unescape(text: str | None) -> str:
    """Android's string escapes to plain text: \\' \\" \\n \\t and \\@ \\?"""
    if text is None:
        return ""
    # Android collapses unquoted whitespace runs, then applies its escapes
    text = re.sub(r"\s+", " ", text.strip())
    if len(text) >= 2 and text[0] == '"' and text[-1] == '"':
        text = text[1:-1]
    out = []
    i = 0
    while i < len(text):
        c = text[i]
        if c == "\\" and i + 1 < len(text):
            n = text[i + 1]
            out.append({"n": "\n", "t": "\t"}.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def parse(xml: str) -> tuple[dict, dict, dict]:
    root = ET.fromstring(xml)
    strings, plurals, arrays = {}, {}, {}
    for el in root:
        name = el.get("name")
        if el.tag == "string":
            strings[name] = unescape("".join(el.itertext()))
        elif el.tag == "plurals":
            plurals[name] = {item.get("quantity"): unescape("".join(item.itertext())) for item in el}
        elif el.tag == "string-array":
            arrays[name] = [unescape("".join(item.itertext())) for item in el]
    return strings, plurals, arrays


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--android", type=Path, help="a local checkout of astiko-ktel-kastorias-app instead of GitHub")
    args = parser.parse_args()

    result = {"plurals": {}, "arrays": {}}
    for language in FOLDERS:
        strings, plurals, arrays = parse(read(language, args.android))
        result[language] = strings
        result["plurals"][language] = plurals
        result["arrays"][language] = arrays

    # Every English key should have a Greek text; the app falls back to English, but say so
    missing = sorted(set(result["en"]) - set(result["el"]))
    if missing:
        print("No Greek for: " + ", ".join(missing), file=sys.stderr)

    text = json.dumps(result, ensure_ascii=False, indent=1, sort_keys=True) + "\n"
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(result['en'])} English and {len(result['el'])} Greek strings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
