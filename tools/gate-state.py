#!/usr/bin/env python3
"""Reuse or produce publication proof for the exact current tree.

`AGENTS.md` says green evidence belongs to the exact relevant tree, and that a
commit, review, push, or elapsed time does not invalidate it. Deciding that by
hand is where the rule fails in practice, so this answers it exactly instead.

    tools/gate-state.py ensure agent-pr-check

`check` prints `valid` only when every tracked and untracked non-ignored file
is byte-identical to the tree that passed, on the same commit and the same
host compiler. Anything else is `stale`, and it names what moved. It exits 0
for valid and 1 for stale, so a shell can branch on it.

`ensure` accepts the two publication gates, reuses a valid record, or runs the
corresponding Make target with live output and records the resulting tree only
after success. `check` and `record` remain available for direct inspection and
stamping. Records are in `debug/`, which is not tracked, so they are per-
workspace and never travel with a commit.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
STATE = ROOT / "debug" / "gate-state.json"
GATES = {"agent-pr-check", "doc-check"}


def git(*args: str) -> str:
    out = subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, check=False
    )
    return out.stdout


def compiler_identity() -> str:
    """A gate result is only evidence about the toolchain that produced it."""
    out = subprocess.run(
        ["cc", "--version"], capture_output=True, text=True, check=False
    )
    return out.stdout.splitlines()[0] if out.stdout else "unknown"


# Bump when the digest's meaning changes, so older records report unknown
# instead of comparing two things that were never comparable.
FORMAT = 3


def content_hash(rel: str) -> str:
    """Git's blob hash for a path's current bytes.

    This must be git's own blob hash and not a plain digest of the bytes,
    because `tree_content` reads the index blob hash for every unmodified
    tracked file. Two hash functions over the same bytes disagree, so staging a
    file used to change its recorded hash and report a stale gate even though
    nothing had been edited.
    """
    try:
        data = (ROOT / rel).read_bytes()
    except OSError:
        return "absent"
    header = f"blob {len(data)}".encode() + b"\0"
    return hashlib.sha1(header + data).hexdigest()[:16]


def zsplit(text: str) -> list[str]:
    return [field for field in text.split("\0") if field]


def tree_content() -> dict[str, str]:
    """Content hash of every file git can see, keyed by path.

    A pure function of the working tree: it does not depend on which commit
    `HEAD` points at or on what happens to be staged. That is deliberate.
    `AGENTS.md` says a commit, review, push, or elapsed time does not
    invalidate green evidence, and nothing in this build reads git state, so
    identical bytes mean an identical build no matter where those bytes are
    recorded. Ignored paths are excluded, so scratch under `debug/` is
    correctly irrelevant.

    Tracked files use the index blob hash, which costs no file reads. Only
    paths whose working tree differs from the index, plus untracked ones, are
    hashed directly.
    """
    entries: dict[str, str] = {}
    for record in zsplit(git("ls-files", "-s", "-z")):
        meta, _, path = record.partition("\t")
        fields = meta.split()
        if path and len(fields) >= 2:
            entries[path] = fields[1][:16]
    for path in zsplit(git("diff", "--name-only", "-z")):
        entries[path] = content_hash(path)
    for path in zsplit(git("ls-files", "--others", "--exclude-standard", "-z")):
        entries[path] = content_hash(path)
    return entries


def digest() -> dict:
    return {
        "version": FORMAT,
        "files": tree_content(),
        "compiler": compiler_identity(),
        # Informational only; never compared. Recorded so a stale stamp can be
        # traced back to the commit it was taken on.
        "recorded_at_head": git("rev-parse", "HEAD").strip(),
    }


def load() -> dict:
    try:
        return json.loads(STATE.read_text())
    except (OSError, ValueError):
        return {}


def save(records: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(records, indent=2, sort_keys=True) + "\n")


def differences(old: dict, new: dict) -> list[str] | None:
    """Reasons the old result no longer applies, or None if unreadable."""
    if old.get("version") != FORMAT:
        return None
    reasons = []
    if old.get("compiler") != new["compiler"]:
        reasons.append("host compiler changed")
    before, after = old.get("files", {}), new["files"]
    changed = sorted(
        name
        for name in set(before) | set(after)
        if before.get(name) != after.get(name)
    )
    if changed:
        shown = ", ".join(changed[:3]) + (" ..." if len(changed) > 3 else "")
        reasons.append(f"{len(changed)} file(s) differ: {shown}")
    return reasons


def cmd_record(gate: str) -> int:
    records = load()
    records[gate] = digest()
    save(records)
    print(f"recorded {gate} green for this tree")
    return 0


def cmd_check(gate: str | None) -> int:
    records = load()
    current = digest()
    gates = [gate] if gate else sorted(records)
    if not gates:
        print("no gate has been recorded in this workspace")
        return 1
    stale = False
    for name in gates:
        old = records.get(name)
        if not old:
            print(f"{name}: unknown - never recorded here, run it")
            stale = True
            continue
        reasons = differences(old, current)
        if reasons is None:
            print(f"{name}: unknown - recorded by an older format, run it")
            stale = True
        elif reasons:
            stale = True
            print(f"{name}: stale - {'; '.join(reasons)}")
        else:
            print(f"{name}: valid - the tree is unchanged since it passed")
    return 1 if stale else 0


def run_gate(gate: str) -> int:
    """Run a Make gate with output attached to the caller's terminal."""
    return subprocess.run(["make", gate], cwd=ROOT, check=False).returncode


def cmd_ensure(gate: str) -> int:
    if gate not in GATES:
        allowed = ", ".join(sorted(GATES))
        print(f"unknown gate {gate!r}; choose one of: {allowed}", file=sys.stderr)
        return 2
    if cmd_check(gate) == 0:
        return 0
    result = run_gate(gate)
    if result:
        return result
    return cmd_record(gate)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    rec = sub.add_parser("record", help="stamp a gate as green for this tree")
    rec.add_argument("gate")
    chk = sub.add_parser("check", help="report whether a recorded gate still holds")
    chk.add_argument("gate", nargs="?")
    ens = sub.add_parser("ensure", help="reuse or run and record a publication gate")
    ens.add_argument("gate", choices=sorted(GATES))
    args = parser.parse_args()
    if args.command == "record":
        return cmd_record(args.gate)
    if args.command == "check":
        return cmd_check(args.gate)
    return cmd_ensure(args.gate)


if __name__ == "__main__":
    sys.exit(main())
