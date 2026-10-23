#!/usr/bin/env python3
"""Builds Resources/emoji.json from Unicode's emoji-test.txt and CLDR annotations (English + French).

Usage: python3 -I scripts/gen_emoji.py
Downloads into .build/emoji-src/ and writes a compact JSON array:
  [emoji, english name, french name, english keywords, french keywords, group index, [5 skin tones] or 0]
"""
import json
import os
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, ".build", "emoji-src")
CLDR = "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json"
FILES = {
    "emoji-test.txt": "https://unicode.org/Public/emoji/latest/emoji-test.txt",
    "en.json": f"{CLDR}/cldr-annotations-full/annotations/en/annotations.json",
    "en-derived.json": f"{CLDR}/cldr-annotations-derived-full/annotationsDerived/en/annotations.json",
    "fr.json": f"{CLDR}/cldr-annotations-full/annotations/fr/annotations.json",
    "fr-derived.json": f"{CLDR}/cldr-annotations-derived-full/annotationsDerived/fr/annotations.json",
}
GROUPS = ["Smileys & Emotion", "People & Body", "Animals & Nature", "Food & Drink", "Travel & Places",
          "Activities", "Objects", "Symbols", "Flags"]
TONES = [chr(c) for c in range(0x1F3FB, 0x1F400)]


def fetch():
    os.makedirs(SRC, exist_ok=True)
    for name, url in FILES.items():
        path = os.path.join(SRC, name)
        if not os.path.exists(path):
            print("downloading", url)
            urllib.request.urlretrieve(url, path)


def annotations(lang):
    out = {}
    for name in (f"{lang}.json", f"{lang}-derived.json"):
        data = json.load(open(os.path.join(SRC, name), encoding="utf-8"))
        node = data.get("annotations") or data.get("annotationsDerived")
        for key, value in node["annotations"].items():
            out[key.replace("️", "")] = (value.get("tts", [""])[0], value.get("default", []))
    return out


def main():
    fetch()
    en, fr = annotations("en"), annotations("fr")
    rows, by_key, group = [], {}, None
    for line in open(os.path.join(SRC, "emoji-test.txt"), encoding="utf-8"):
        if line.startswith("# group:"):
            name = line.split(":", 1)[1].strip()
            group = GROUPS.index(name) if name in GROUPS else None
            continue
        if group is None or line.startswith("#") or "; fully-qualified" not in line:
            continue
        emoji = line.split("#", 1)[1].strip().split(" ")[0]
        test_name = line.split("#", 1)[1].strip().split(" ", 2)[2]
        key = emoji.replace("️", "")
        tones = [t for t in TONES if t in emoji]
        if tones:
            # Only uniform-tone variants (all modifiers identical) get attached to their base emoji.
            if len(set(tones)) == 1:
                base = key
                for t in TONES:
                    base = base.replace(t, "")
                by_key.setdefault(base + "#tones", {})[tones[0]] = emoji
            continue
        en_name, en_kw = en.get(key, (test_name, []))
        fr_name, fr_kw = fr.get(key, ("", []))
        row = [emoji, en_name or test_name, fr_name, "|".join(en_kw), "|".join(fr_kw), group, 0]
        rows.append(row)
        by_key[key] = row
    for key, row in list(by_key.items()):
        if key.endswith("#tones"):
            base = by_key.get(key[:-6])
            if base and len(row) == 5:
                base[6] = [row[t] for t in TONES]
    out = os.path.join(ROOT, "Resources", "emoji.json")
    json.dump(rows, open(out, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    print(f"wrote {len(rows)} emoji ({sum(1 for r in rows if r[6])} with skin tones) to {out}")


if __name__ == "__main__":
    sys.exit(main())
