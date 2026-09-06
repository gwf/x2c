#!/usr/bin/env python3
"""Keep runnable gallery examples identical to the slides, including hidden lines.

Use --update after editing a slide to refresh its standalone source. Execution
and expected output remain owned by examples/check.sh and packages-check.
"""

import argparse
import importlib.util
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "doc_examples", ROOT / "tools/check-doc-examples.py")
doc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(doc)


def check(update=False):
    slides = ROOT / "site/src/content/slides"
    entries = json.loads((ROOT / "examples/gallery.json").read_text())
    errors = []
    seen = set()
    examples = set()
    for entry in entries:
        name = entry["slide"]
        if name in seen:
            errors.append(f"{name}: duplicate gallery entry")
        seen.add(name)
        if entry["example"] in examples:
            errors.append(f"{name}: duplicate standalone example")
        examples.add(entry["example"])
        slide = slides / name
        if not slide.is_file():
            errors.append(f"{name}: gallery source is missing")
            continue
        language = entry.get("language", "x2c")
        if language == "sh":
            target = ROOT / "examples" / entry["example"]
            blocks = [m.group("body") for m in doc.FENCE_PATTERN.finditer(
                slide.read_text()) if m.group("info") == "sh"]
            actual = [m.group("body") for m in doc.FENCE_PATTERN.finditer(
                target.read_text() if target.exists() else "")
                if m.group("info") == "sh"]
            if blocks != actual or not blocks:
                errors.append(f"{target.relative_to(ROOT)}: shell recipe differs from {name}")
            continue
        samples = doc.collect(slide, errors)
        if len(samples) != 1:
            errors.append(f"{name}: expected one runnable x2c sample")
            continue
        target = ROOT / "examples" / (entry["example"] + ".x")
        expected = samples[0].code
        if update:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(expected)
        elif not target.exists() or target.read_text() != expected:
            errors.append(
                f"{target.relative_to(ROOT)}: missing or differs from {name}; "
                "run python3 tools/check-gallery-examples.py --update")
    for path in sorted(slides.glob("*.md")):
        if path.name not in seen:
            errors.append(f"{path.name}: no standalone example declared")
    rows = {}
    for line in (ROOT / "examples/manifest.txt").read_text().splitlines():
        if line and not line.startswith("#"):
            row = line.split("|")
            rows[row[0]] = row
    for entry in entries:
        if entry.get("language") == "sh":
            continue
        row = rows.get(entry["example"])
        wanted = "none" if entry.get("optional") else "run"
        if row is None or row[2] != wanted:
            errors.append(f'{entry["example"]}: missing {wanted} manifest coverage')
    return entries, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    entries, errors = check(args.update)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Gallery: {len(entries)} slides have synchronized examples")
    return 0


if __name__ == "__main__":
    sys.exit(main())
