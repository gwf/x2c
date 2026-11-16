#!/usr/bin/env python3
"""Check and extract a staged production website before its promotion."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile


def select(archive, source_sha, run, live_release, output):
    """`run` is the staging workflow run that built `archive`; `live_release`
    is the release-candidate.json production serves now."""
    if (run["conclusion"], run["event"], run["path"], run["head_branch"]) != \
            ("success", "workflow_dispatch", ".github/workflows/stage.yml", "dev"):
        raise ValueError("website run is not a successful staging run from dev")
    with tarfile.open(archive) as tar:
        tar.extractall(output, filter="data")
    receipt = json.loads((output / "website-deployment.json").read_text())
    if (receipt["destination"], receipt["source_sha"]) != ("production", source_sha):
        raise ValueError("archive is not the production website of that source")
    retained = json.loads((output / "release-candidate.json").read_text())
    if retained != live_release or \
            receipt["retained_candidate"] != retained["identity"]:
        raise ValueError("archive retains a release production no longer serves")
    for path, digest in receipt["preserved_sha256"].items():
        if hashlib.sha256((output / path).read_bytes()).hexdigest() != digest:
            raise ValueError(f"retained release file differs: {path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--live-release", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    select(args.archive, args.source_sha, json.loads(args.run.read_text()),
           json.loads(args.live_release.read_text()), args.output)
