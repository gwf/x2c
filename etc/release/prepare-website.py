#!/usr/bin/env python3
"""Archive a new website while retaining the staged release byte for byte."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import tarfile

PRESERVED = ("install.sh", "x2c-version.txt", "release-candidate.json",
             "packages", "CNAME", "x2c-book.pdf")


def prepare(site, staged, source_sha, output):
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise ValueError("website source must be a full commit SHA")
    release = json.loads((staged / "release-candidate.json").read_text())
    if release["destination"] != "staging":
        raise ValueError("expected a staged release")
    if (staged / "CNAME").read_text().strip() != "staging.x2c-lang.dev":
        raise ValueError("unexpected staging domain")
    html = (site / "index.html").read_text()
    if (f'name="x2c-site-source" content="{source_sha}"' not in html or
            f'name="x2c-candidate" content="{release["identity"]}"' not in html):
        raise ValueError("built website provenance does not match selection")
    preserved = {}
    for name in PRESERVED:
        source, target = staged / name, site / name
        if name == "x2c-book.pdf" and not source.exists():
            continue
        if not source.exists():
            raise ValueError(f"missing staged release file: {name}")
        if target.is_dir():
            shutil.rmtree(target)
        elif target.exists():
            target.unlink()
        if source.is_dir():
            shutil.copytree(source, target)
            paths = sorted(source.rglob("*"))
        else:
            shutil.copyfile(source, target)
            paths = [source]
        for path in paths:
            if path.is_file():
                relative = path.relative_to(staged).as_posix()
                preserved[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    (site / "website-deployment.json").write_text(json.dumps({
        "source_sha": source_sha, "staged_candidate": release["identity"],
        "preserved_sha256": preserved,
    }, indent=2) + "\n")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(output, "w:gz") as archive:
        for path in sorted(site.iterdir()):
            archive.add(path, arcname=path.name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site", type=Path, required=True)
    parser.add_argument("--staged", type=Path, required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    prepare(args.site, args.staged, args.source_sha, args.output)
