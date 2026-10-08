#!/usr/bin/env python3
"""Helpers for Compositor's String Catalogs (Korean).

  scripts/l10n.py status [--list]
      Keys that still need Korean in Compositor/Localizable.xcstrings and Compositor/InfoPlist.xcstrings. Stale
      keys and keys marked do-not-translate don't count. Exits 1 while any remain.
  scripts/l10n.py set FILE.json
      Applies {"English key": "한국어", "Other key": null} to every catalog that holds each key; null marks the key
      do-not-translate. The Korean must read the same format arguments as the key, each as the same type (reorder
      them with numbered specifiers such as %2$@). Nothing is written if any pair fails.
  scripts/l10n.py manual KEY [KEY...]
      Adds keys the compiler can't see (enum raw values, shortcut titles) to Localizable.xcstrings, marked manual so
      syncs keep them.
  scripts/l10n.py symbols
      Marks keys with no letters ("%lld", "·", "100%") do-not-translate.
  scripts/l10n.py where DERIVED_DATA [PATH_PREFIX...] [--untranslated]
      Prints "file<TAB>key<TAB>korean" for keys used in source files starting with the prefixes, from the last
      build's .stringsdata files.

Run a catalog sync (xcodebuild -exportLocalizations) after `set`, `manual` or `symbols`; it rewrites the catalog in
Xcode's own layout.
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOGS = [os.path.join(ROOT, "Compositor", name) for name in ("Localizable.xcstrings", "InfoPlist.xcstrings")]
# A printf-style specifier: optional argument number, flags (no space, so "50% off" isn't one), width, precision,
# length and conversion. "%%" is a literal percent sign. A "*" width or precision reads an argument of its own; it's
# captured so it can be refused.
SPECIFIER = re.compile(r"%(?:(\d+)\$)?[-+#0]*(\*|\d*)(?:\.(\*|\d+))?(hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfFeEgGaAcCsSp%])")


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save(path, catalog):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2, separators=(",", " : "))
        f.write("\n")


def catalogs():
    return [(path, load(path)) for path in CATALOGS if os.path.exists(path)]


def korean(entry):
    unit = entry.get("localizations", {}).get("ko", {}).get("stringUnit", {})
    return unit.get("value") if unit.get("state") == "translated" else None


def needs_korean(entry):
    return entry.get("shouldTranslate", True) and entry.get("extractionState") != "stale" and korean(entry) is None


def arguments(text):
    """Every format argument `text` reads, as sorted (argument number, conversion) pairs, one per use; None when it
    numbers some arguments and not others, or uses a "*" width or precision."""
    found, unnumbered, numbered = [], 0, False
    for match in SPECIFIER.finditer(text):
        number, width, precision, length, conversion = match.groups()
        if conversion == "%":
            continue
        if width == "*" or precision == "*":
            return None
        if number is None:
            unnumbered += 1
            index = unnumbered
        else:
            numbered = True
            index = int(number)
        found.append((index, (length or "") + conversion))
    if numbered and unnumbered:
        return None
    return sorted(found)


def same_arguments(key, value):
    """True when `value` reads exactly the arguments `key` does, as often and each as the same type; numbered
    specifiers ("%2$@") may reorder them."""
    wanted = arguments(key)
    return wanted is not None and arguments(value) == wanted


def cmd_status(args):
    total = 0
    for path, catalog in catalogs():
        missing = [key for key, entry in catalog["strings"].items() if needs_korean(entry)]
        total += len(missing)
        print(f"{os.path.relpath(path, ROOT)}: {len(missing)} untranslated")
        if "--list" in args:
            for key in missing:
                print("  " + json.dumps(key, ensure_ascii=False))
    return 1 if total else 0


def cmd_set(args):
    pairs = load(args[0])
    loaded = catalogs()
    errors = []
    for key, value in pairs.items():
        # A key can be in both catalogs ("Compositor Project" is a document type and may be UI text too).
        found = [catalog["strings"][key] for _, catalog in loaded if key in catalog["strings"]]
        if not found:
            errors.append(f"not in any catalog (sync first, or add it with `manual`): {key!r}")
            continue
        if value is not None and not same_arguments(key, value):
            errors.append(f"format specifiers differ: {key!r} -> {value!r}")
            continue
        for entry in found:
            if value is None:
                entry["shouldTranslate"] = False
                entry.get("localizations", {}).pop("ko", None)
            else:
                entry.pop("shouldTranslate", None)
                entry.setdefault("localizations", {})["ko"] = {"stringUnit": {"state": "translated", "value": value}}
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    for path, catalog in loaded:
        save(path, catalog)
    print(f"set {len(pairs)} keys")
    return 0


def cmd_manual(args):
    path, catalog = catalogs()[0]
    added = 0
    for key in args:
        # An extracted or stale key is marked too: a run-time lookup still needs it after the literal that was
        # extracted goes away. Its translation stays.
        entry = catalog["strings"].setdefault(key, {})
        if entry.get("extractionState") != "manual":
            entry["extractionState"] = "manual"
            added += 1
    save(path, catalog)
    print(f"added {added} manual keys")
    return 0


def cmd_symbols(args):
    path, catalog = catalogs()[0]
    marked = 0
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate", True) and not any(ch.isalpha() for ch in SPECIFIER.sub("", key)):
            entry["shouldTranslate"] = False
            marked += 1
    save(path, catalog)
    print(f"marked {marked} keys do-not-translate")
    return 0


def cmd_where(args):
    untranslated = "--untranslated" in args
    args = [arg for arg in args if arg != "--untranslated"]
    derived, prefixes = args[0], args[1:]
    entries = {key: entry for _, catalog in catalogs() for key, entry in catalog["strings"].items()}
    pattern = os.path.join(derived, "Build/Intermediates.noindex/Compositor.build/*/Compositor.build/"
                                    "Objects-normal/*/*.stringsdata")
    rows = set()
    for data in glob.glob(pattern):
        info = load(data)
        source = os.path.relpath(os.path.realpath(info["source"]), os.path.realpath(ROOT))
        if source.startswith("..") or not os.path.exists(os.path.join(ROOT, source)):
            continue
        if prefixes and not any(source.startswith(prefix) for prefix in prefixes):
            continue
        for item in info["tables"].get("Localizable", []):
            entry = entries.get(item["key"], {})
            if untranslated and not needs_korean(entry):
                continue
            rows.add((source, item["key"], korean(entry) or ""))
    for source, key, value in sorted(rows):
        print(f"{source}\t{json.dumps(key, ensure_ascii=False)}\t{value}")
    return 0


def main():
    commands = {"status": cmd_status, "set": cmd_set, "manual": cmd_manual, "symbols": cmd_symbols,
                "where": cmd_where}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        print(__doc__)
        return 2
    return commands[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
