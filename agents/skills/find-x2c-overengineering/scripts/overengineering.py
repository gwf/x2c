#!/usr/bin/env python3
"""Build a bounded forensic queue for possible x2c overengineering.

The scores in this program select source for human review. They are not
findings and never authorize deletion.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
from typing import Iterable


ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools"))
from x2c_source import function_spans, mask_non_code  # noqa: E402

FORMAT_VERSION = 1
DEFAULT_BUDGET = 5
GENERATED = {"lib/x2c.x"}
MACHINERY = re.compile(
    r"(?i)\b(?:cache|ledger|registry|replay|reconcile|snapshot|index|table|"
    r"state|phase|validator|validate|analysis|analyze|tracking|bookkeep|"
    r"pending|seen|visited|generation|epoch|fallback)\b"
)
BOOKKEEPING = re.compile(
    r"(?m)(?:\[[^\]]+\]\s*=|\.set\s*\(|\.remove\s*\(|\.append\s*\(|"
    r"\b(?:count|depth|generation|epoch|state)\s*(?:\+\+|--|[+\-]?=))"
)
TYPE_RE = re.compile(
    r"(?m)^(?P<static>static\s+)?(?:typedef\s+)?"
    r"(?P<kind>struct|enum)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\{"
)
HUNK_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def run(args: list[str], cwd: pathlib.Path = ROOT, check: bool = True) -> str:
    done = subprocess.run(
        args, cwd=cwd, text=True, capture_output=True, check=False
    )
    if check and done.returncode:
        raise SystemExit(done.stderr.strip() or "command failed: " + " ".join(args))
    return done.stdout


def digest(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def source_paths(root: pathlib.Path) -> list[pathlib.Path]:
    paths = list((root / "src").rglob("*.x"))
    paths.extend((root / "lib").rglob("*.x"))
    return sorted(
        path for path in paths
        if path.relative_to(root).as_posix() not in GENERATED
    )


def line_at(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def preceding_public(text: str, start: int) -> bool:
    prefix = text[:start].splitlines()
    for line in reversed(prefix[-4:]):
        stripped = line.strip()
        if not stripped or stripped.startswith("/*") or stripped.startswith("*"):
            continue
        return stripped == "#pragma public"
    return False


def symbol_references(symbol: str, texts: dict[str, str], own_path: str) -> int:
    pattern = re.compile(rf"(?<![A-Za-z0-9_]){re.escape(symbol)}\s*\(")
    count = sum(len(pattern.findall(text)) for text in texts.values())
    # One occurrence is normally the declaration itself.
    return max(0, count - 1)


def test_references(symbol: str, root: pathlib.Path) -> int:
    if not (root / "unittest").exists():
        return 0
    output = run(
        ["git", "grep", "-l", "-F", symbol, "--", "unittest"], root, False
    )
    return len([line for line in output.splitlines() if line])


def audit_overlaps(root: pathlib.Path) -> list[dict]:
    tool = root / "tools" / "audit-source-bloat.py"
    if not tool.exists():
        return []
    done = subprocess.run(
        [sys.executable, str(tool), "--json", "src", "lib"],
        cwd=root, text=True, capture_output=True, check=False,
    )
    if done.returncode:
        return []
    try:
        return json.loads(done.stdout).get("findings", [])
    except (ValueError, AttributeError):
        return []


def overlap_score(path: str, start: int, end: int, findings: list[dict]) -> int:
    score = 0
    for finding in findings:
        for item in finding.get("paths", []):
            if item.get("path") != path:
                continue
            if any(a <= end and b >= start for a, b in item.get("ranges", [])):
                score = max(score, min(15, finding.get("score", 0) // 2))
    return score


def history(path: str, start: int, end: int, root: pathlib.Path) -> dict:
    blame = run(
        ["git", "blame", "--line-porcelain", f"-L{start},{end}", "HEAD", "--", path],
        root, False,
    )
    commits = []
    subjects = {}
    times = {}
    current = None
    for line in blame.splitlines():
        if re.match(r"^[0-9a-f^]{8,40} ", line):
            current = line.split()[0].lstrip("^")
            commits.append(current)
        elif line.startswith("summary ") and current:
            subjects[current] = line[8:]
        elif line.startswith("author-time ") and current:
            times[current] = int(line[12:])
    counts = collections.Counter(commits)
    top = [
        {"commit": sha, "lines": count, "subject": subjects.get(sha, "")}
        for sha, count in counts.most_common(4)
    ]
    repair = sum(
        count for sha, count in counts.items()
        if re.search(r"(?i)\b(?:fix|repair|restore|revert|correct|follow)",
                     subjects.get(sha, ""))
    )
    observed_times = [times[sha] for sha in counts if sha in times]
    concentration = max(counts.values(), default=0) / max(1, len(commits))
    rapid = (len(counts) >= 3 and observed_times and
             max(observed_times) - min(observed_times) <= 7 * 24 * 60 * 60)
    return {"top_commits": top, "repair_lines": repair,
            "commit_count": len(counts), "concentration": concentration,
            "rapid_churn": bool(rapid)}


def inventory(root: pathlib.Path) -> dict:
    paths = source_paths(root)
    texts = {path.relative_to(root).as_posix(): path.read_text(errors="replace")
             for path in paths}
    audit = audit_overlaps(root)
    regions = []
    for path, raw in texts.items():
        masked = mask_non_code(raw)
        for span in function_spans(masked, include_static=True):
            body = raw[span.declaration_start:span.end]
            start = line_at(raw, span.declaration_start)
            end = line_at(raw, max(span.declaration_start, span.end - 1))
            public = preceding_public(raw, span.declaration_start)
            lines = end - start + 1
            signals = []
            score = 0
            term_hits = len(MACHINERY.findall(body))
            if term_hits:
                points = min(12, 2 + term_hits)
                score += points
                signals.append(f"{term_hits} machinery terms")
            book_hits = len(BOOKKEEPING.findall(body))
            if book_hits >= 2:
                points = min(10, book_hits)
                score += points
                signals.append(f"{book_hits} bookkeeping operations")
            if span.name.startswith("_") and lines >= 30:
                points = min(9, 3 + lines // 40)
                score += points
                signals.append(f"private {lines}-line function")
            audit_points = overlap_score(path, start, end, audit)
            if audit_points:
                score += audit_points
                signals.append(f"source-bloat overlap +{audit_points}")
            if not signals:
                signals.append("no mechanical signal")
            region = {
                "candidate_id": f"{path}:{span.name}",
                "path": path,
                "symbol": span.name,
                "kind": "function",
                "start": start,
                "end": end,
                "lines": lines,
                "public": public or not span.name.startswith("_"),
                "production_call_sites": None,
                "test_name_references": None,
                "source_digest": digest(body),
                "score": score,
                "signals": signals,
            }
            regions.append(region)
        # Private top-level schemas are candidates only when substantial.
        for match in TYPE_RE.finditer(masked):
            opening = masked.find("{", match.start(), match.end())
            closing = masked.find("};", opening)
            if closing < 0 or match.group("static") is None:
                continue
            body = raw[match.start():closing + 2]
            start, end = line_at(raw, match.start()), line_at(raw, closing + 1)
            fields = body.count(";") if match.group("kind") == "struct" else body.count(",") + 1
            if fields < 5:
                continue
            name = match.group("name")
            regions.append({
                "candidate_id": f"{path}:{name}", "path": path,
                "symbol": name, "kind": match.group("kind"), "start": start,
                "end": end, "lines": end - start + 1, "public": False,
                "production_call_sites": len(re.findall(rf"\b{re.escape(name)}\b", raw)) - 1,
                "test_name_references": None,
                "source_digest": digest(body), "score": min(15, 5 + fields),
                "signals": [f"private {match.group('kind')} with {fields} members"],
            })
    # Enrich only plausible private mechanisms; public code is retained in the
    # inventory but receives no low-consumer priority.
    # History and reference searches are the expensive part. Apply them only
    # to a short mechanical shortlist; the skill reads at most five of these.
    for region in sorted(regions, key=lambda x: -x["score"])[:12]:
        refs = symbol_references(region["symbol"], texts, region["path"])
        region["production_call_sites"] = refs
        if region["kind"] == "function" and refs <= 2:
            points = min(6, (2 - refs) * 2 + 2)
            region["score"] += points
            region["signals"].append(f"{refs} production call sites")
        region["history"] = history(
            region["path"], region["start"], region["end"], root
        )
        region["test_name_references"] = test_references(
            region["symbol"], root
        )
        repair = region["history"]["repair_lines"]
        if repair:
            region["score"] += min(8, 1 + repair // 10)
            region["signals"].append(f"{repair} lines last touched by repair-like commits")
        if region["history"]["concentration"] >= 0.70 and region["lines"] >= 40:
            region["score"] += 4
            region["signals"].append("at least 70% of lines share one origin commit")
        if region["history"]["rapid_churn"]:
            region["score"] += 4
            region["signals"].append("three or more line origins landed within seven days")
    regions.sort(key=lambda item: (-item["score"], item["candidate_id"]))
    tree_digest = digest("".join(
        path + "\0" + digest(texts[path]) for path in sorted(texts)
    ))
    return {"format_version": FORMAT_VERSION, "head": run(
        ["git", "rev-parse", "HEAD"], root
    ).strip(), "source_digest": tree_digest, "paths": sorted(texts),
        "regions": regions}


def repository_id(root: pathlib.Path) -> str:
    common = run(["git", "rev-parse", "--git-common-dir"], root).strip()
    path = (root / common).resolve() if not os.path.isabs(common) else pathlib.Path(common)
    return hashlib.sha256(str(path).encode()).hexdigest()[:12]


def state_root(root: pathlib.Path, override: str | None) -> pathlib.Path:
    if override:
        return pathlib.Path(override).expanduser()
    return pathlib.Path.home() / ".codex" / "x2c-overengineering" / repository_id(root)


def previous_attempts(base: pathlib.Path) -> set[tuple[str, str]]:
    attempted = set()
    for selection in base.glob("runs/*/selection.json"):
        try:
            data = json.loads(selection.read_text())
        except (OSError, ValueError):
            continue
        for item in data.get("selected", []):
            attempted.add((item["candidate_id"], item["source_digest"]))
    return attempted


def unique_run_dir(base: pathlib.Path, head: str) -> pathlib.Path:
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    candidate = base / "runs" / f"{stamp}-{head[:12]}"
    suffix = 2
    while candidate.exists():
        candidate = base / "runs" / f"{stamp}-{head[:12]}-{suffix}"
        suffix += 1
    candidate.mkdir(parents=True)
    return candidate


def bounded_selection(regions: list[dict], attempted: set[tuple[str, str]],
                      budget: int) -> list[dict]:
    """Choose distinct source neighborhoods so one mechanism gets one slot."""
    selected = []
    for item in regions:
        if item["public"]:
            continue
        if (item["candidate_id"], item["source_digest"]) in attempted:
            continue
        if any(
            prior["path"] == item["path"]
            and item["start"] <= prior["end"] + 80
            and prior["start"] <= item["end"] + 80
            for prior in selected
        ):
            continue
        selected.append(item)
        if len(selected) == budget:
            break
    return selected


def scan(args: argparse.Namespace) -> int:
    root = pathlib.Path(args.root).resolve()
    report = inventory(root)
    base = state_root(root, args.state_root)
    attempted = previous_attempts(base)
    eligible = [
        item for item in report["regions"]
        if not item["public"]
        and (item["candidate_id"], item["source_digest"]) not in attempted
    ]
    selected = bounded_selection(report["regions"], attempted, args.budget)
    run_dir = unique_run_dir(base, report["head"])
    (run_dir / "inventory.json").write_text(json.dumps(report, indent=2) + "\n")
    selection = {
        "format_version": FORMAT_VERSION, "budget": args.budget,
        "selected": selected, "eligible_count": len(eligible),
    }
    (run_dir / "selection.json").write_text(json.dumps(selection, indent=2) + "\n")
    (run_dir / "attempts.jsonl").write_text("")
    command = shlex.join([
        "python3",
        "agents/skills/find-x2c-overengineering/scripts/overengineering.py",
        "--root", str(root), "scan", "--budget", str(args.budget),
        "--state-root", str(base),
    ]) + "\n"
    (run_dir / "commands.txt").write_text(command)
    rows = ["# Overengineering forensic run", "", f"Head: `{report['head']}`",
            f"Source digest: `{report['source_digest']}`", "",
            "## Selected regions", ""]
    for item in selected:
        rows.append(
            f"- `{item['candidate_id']}` `{item['path']}:{item['start']}-{item['end']}` "
            f"score {item['score']}: {'; '.join(item['signals'])}"
        )
    rows.extend(["", "## Reviewed attempts", "",
                 "Record each candidate, empty search, or refutation here.", ""])
    (run_dir / "report.md").write_text("\n".join(rows))
    print(run_dir)
    print(json.dumps(selection, indent=2))
    return 0


def parse_diff(commit: str, root: pathlib.Path) -> list[tuple[str, int, int]]:
    text = run([
        "git", "diff", "--find-renames", "--unified=0", f"{commit}^", commit,
        "--", "src", "lib"
    ], root)
    old_path = None
    ranges = []
    for line in text.splitlines():
        if line.startswith("--- a/"):
            old_path = line[6:]
        elif line.startswith("--- /dev/null"):
            old_path = None
        else:
            match = HUNK_RE.match(line)
            if match and old_path and old_path not in GENERATED:
                start, count = int(match.group(1)), int(match.group(2) or 1)
                if count:
                    ranges.append((old_path, start, count))
    return ranges


def is_root_commit(commit: str, root: pathlib.Path) -> bool:
    fields = run(["git", "rev-list", "--parents", "-n", "1", commit], root,
                 False).split()
    return len(fields) == 1


def deletion_report(commit: str, root: pathlib.Path) -> dict:
    counts: collections.Counter[tuple[str, str]] = collections.Counter()
    total = 0
    ranges = parse_diff(commit, root)
    for path, start, count in ranges:
        blame = run([
            "git", "blame", "--line-porcelain", f"-L{start},+{count}",
            f"{commit}^", "--", path
        ], root, False)
        current = None
        subject = ""
        pending = 0
        for line in blame.splitlines():
            if re.match(r"^[0-9a-f^]{8,40} ", line):
                current = line.split()[0].lstrip("^")
                pending += 1
            elif line.startswith("summary "):
                subject = line[8:]
            elif line.startswith("\t") and current:
                counts[(current, subject)] += 1
                total += 1
                pending = max(0, pending - 1)
    return {
        "format_version": FORMAT_VERSION, "deletion_commit": commit,
        "removed_parent_lines": total,
        "ranges": [{"path": p, "start": s, "count": c} for p, s, c in ranges],
        "origins": [
            {"commit": sha, "subject": subject, "lines": count,
             "provenance_wall": is_root_commit(sha, root)}
            for (sha, subject), count in counts.most_common()
        ],
    }


def trace_deletion(args: argparse.Namespace) -> int:
    root = pathlib.Path(args.root).resolve()
    result = deletion_report(args.commit, root)
    print(json.dumps(result, indent=2))
    return 0


def arguments(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=str(ROOT))
    sub = parser.add_subparsers(dest="command", required=True)
    scan_parser = sub.add_parser("scan")
    scan_parser.add_argument("--budget", type=int, default=DEFAULT_BUDGET)
    scan_parser.add_argument("--state-root")
    trace = sub.add_parser("trace-deletion")
    trace.add_argument("commit")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = arguments(argv)
    if args.command == "scan":
        if args.budget < 1:
            raise SystemExit("--budget must be positive")
        return scan(args)
    return trace_deletion(args)


if __name__ == "__main__":
    raise SystemExit(main())
