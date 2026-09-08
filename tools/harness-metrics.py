#!/usr/bin/env python3
"""Summarize how agent sessions actually behaved, from local transcripts.

This reads Claude Code and Codex session transcripts on this machine and
reports observed skills, build requests, edits, and rework commands. It writes
only aggregate counts, never transcript text. Requests do not establish that
a build executed or succeeded, or that a repeated request wasted work.

make_gate_requests counts explicit Make requests for publication gates,
broad checks, safe builds, and stage comparisons listed in GATE_TARGETS.
ensure_gate_requests counts gate-state ensure requests, which may reuse cached
evidence. Both contribute to per-session targets; only Make requests contribute
to make_alias and make_canonical. These fields replace broad_gates and remove
broad_gates_redundant and its percentage. Regenerate historical reports with
this version before comparing them.

The point is to make a harness change measurable. Record a summary before
changing instructions or skills, change them, then record another and compare.
Nothing in the build or test process consumes this, and it must never become
one.

    tools/harness-metrics.py --since 2026-08-01
    tools/harness-metrics.py --json > plans/harness-baseline.json
    tools/harness-metrics.py --by-day        # sessions by start day

Transcripts are private. Keep the output aggregate and keep the raw sessions
out of the repository.
"""

from __future__ import annotations

import argparse
import collections
import glob
import json
import os
import re
import sys

from x2c_reply import WORD_LIMIT, measure, text_of

DEFAULT_CLAUDE_ROOT = "~/.claude/projects"
DEFAULT_CODEX_ROOT = "~/.codex/sessions"

# Map build aliases to the documented targets to measure which spellings
# agents use.
ALIASES = {
    "x2c": "build", "safely": "build-safe", "unittest": "verify",
    "stresstest": "stage-3", "selftest": "stage-2", "test": "stage-1",
    "check-docs": "doc-check", "docs": "doc-generate",
    "compiler-fixtures": "verify-fixtures",
    "update-compiler-fixtures": "verify-fixtures-update",
    "diff0": "stage-diff-0", "diff1": "stage-diff-1",
    "diff2": "stage-diff-2", "diff3": "stage-diff-3",
    "check-symbol-snapshot": "sym-check", "update-symbol-snapshot": "sym-update",
    "check-header-symbols": "hdr-check", "update-header-symbols": "hdr-sync",
    "symbol-table": "sym-refresh", "benchmarks": "bm-all", "book": "doc-build",
    "sanitizer-unittest": "verify-sanitize", "refresh-artifacts": "artifact-refresh",
    "rebootstrap": "bootstrap-refresh", "bootstrap": "bootstrap-build",
    "update-examples": "examples-update", "check-doc-examples": "doc-examples",
    "shootout": "shoot-run", "install": "build-install",
}

# Canonical Make targets grouped as gate requests; this includes doc-check
# so both publication gates can be compared with their ensure requests.
GATE_TARGETS = {
    "precommit", "check", "agent-pr-check", "doc-check", "stage-3",
    "build-safe", "stage-diff-all", "verify-sanitize",
}

PROJECT_SKILLS = {
    "plan-x2c-change", "execute-x2c-plan", "fix-x2c-bug", "review-x2c-repo",
    "simplify-x2c-source", "clean-x2c-source", "find-comment-slop",
    "find-redundant-validation", "integrate-x2c-package",
    "improve-x2c-agent-process", "agent-failure", "develop-x2c",
}

SOURCE_EDIT = re.compile(
    r"(?:^|/)(src|lib|unittest|examples|etc|tools|include)/"
)
# A target command that starts a command, not one named inside `pgrep -f`.
# Agents run a long gate in the background and poll for it, and counting each
# poll as a run inflated the broad-gate count 2.1x.
COMMAND_START = (
    r"(?:^|[;&|({]\s*|\n\s*)(?:(?:time|nohup|do|then|else)\s+)*"
    r"(?:[A-Za-z_]+=\S+\s+)*"
)
MAKE = re.compile(
    COMMAND_START
    + r"make\s+(?:-[a-zA-Z]\S*\s+)*([a-z0-9][a-z0-9-]*)"
)
ENSURE = re.compile(
    COMMAND_START
    + r"(?:\./)?tools/gate-state\.py\s+ensure\s+"
    r"(agent-pr-check|doc-check)\b"
)
PUSH_REFSPEC = re.compile(r"git push\s+.*(HEAD:refs/heads/|:refs/heads/)")
PUSH_PLAIN = re.compile(r"git push(?!\s+.*refs/heads/)")
REWORK = {
    "stash": re.compile(r"\bgit stash\b"),
    "revert_file": re.compile(r"\bgit checkout\s+(--\s+)?[a-z]\S*\.(x|xmacro|md|py|sh)"),
    "reset": re.compile(r"\bgit reset\b"),
    "amend": re.compile(r"\bgit commit\b.*--amend"),
    "force_push": re.compile(r"\bgit push\b.*(--force|-f\b)"),
}
CODEX_COMMAND = re.compile(
    r'(?:"cmd"|\bcmd)\s*:\s*("(?:\\.|[^"\\])*")'
)
SKILL_PATH = re.compile(r"([A-Za-z0-9_-]+)/SKILL\.md")
QUOTED_WORD = re.compile(r'''\\.|'[^']*'|"(?:\\.|[^"\\])*"''')


def blocks(record):
    message = record.get("message") or {}
    content = message.get("content")
    return content if isinstance(content, list) else []


def command_targets(command: str, pattern):
    """The requested targets, skipping matches inside a quoted word."""
    unquoted = QUOTED_WORD.sub('""', command)
    for match in pattern.finditer(unquoted):
        yield match.group(1)


def codex_commands(source: str):
    """Yield shell commands embedded in a Codex orchestration call."""
    for match in CODEX_COMMAND.finditer(source):
        try:
            yield json.loads(match.group(1))
        except (TypeError, ValueError):
            continue


def count_command(command, stat, targets):
    for target in command_targets(command, MAKE):
        targets[target] += 1
        key = "alias" if target in ALIASES else "canonical"
        stat[f"make_{key}"] += 1
        if ALIASES.get(target, target) in GATE_TARGETS:
            stat["make_gate_requests"] += 1
    for target in command_targets(command, ENSURE):
        targets[target] += 1
        stat["ensure_gate_requests"] += 1
    if PUSH_REFSPEC.search(command):
        stat["push_refspec"] += 1
    elif PUSH_PLAIN.search(command):
        stat["push_plain"] += 1
    for label, pattern in REWORK.items():
        if pattern.search(command):
            stat[f"rework_{label}"] += 1


def add_reply(reply: str, stat, words) -> None:
    count, furniture = measure(reply)
    words.append(count)
    stat["replies"] += 1
    if count > WORD_LIMIT:
        stat["replies_long"] += 1
    if furniture:
        stat["replies_furniture"] += 1


def codex_session(path: str, since: str | None, until: str | None,
                  project_match: str) -> dict | None:
    stat = collections.Counter(make_gate_requests=0, ensure_gate_requests=0)
    skills = collections.Counter()
    targets = collections.Counter()
    days = set()
    words: list[int] = []
    workspace = ""
    session_id = ""
    patch_calls = set()

    try:
        handle = open(path, errors="replace")
    except OSError:
        return None

    with handle:
        for line in handle:
            try:
                record = json.loads(line)
            except ValueError:
                continue
            payload = record.get("payload") or {}
            if not isinstance(payload, dict):
                continue
            if record.get("type") == "session_meta":
                workspace = str(payload.get("cwd") or workspace)
                session_id = str(
                    payload.get("session_id") or payload.get("id") or session_id
                )
            stamp = (
                record.get("timestamp") or payload.get("timestamp") or ""
            )[:10]
            if stamp:
                if since and stamp < since:
                    continue
                if until and stamp > until:
                    continue
                days.add(stamp)

            kind = payload.get("type")
            if record.get("type") == "event_msg":
                if (kind == "agent_message"
                        and payload.get("phase") == "final_answer"):
                    reply = str(payload.get("message") or "").strip()
                    if reply:
                        add_reply(reply, stat, words)
                elif kind == "patch_apply_end" and payload.get("success"):
                    call_id = payload.get("call_id")
                    if call_id and call_id in patch_calls:
                        continue
                    if call_id:
                        patch_calls.add(call_id)
                    changed = payload.get("changes") or {}
                    if isinstance(changed, dict) and changed:
                        stat["edits"] += 1
                        if any(
                            SOURCE_EDIT.search(str(changed_path))
                            for changed_path in changed
                        ):
                            stat["source_edits"] += 1
                elif (kind == "sub_agent_activity"
                      and payload.get("kind") == "started"):
                    stat["subagents"] += 1
                continue

            if record.get("type") != "response_item" or kind not in (
                "custom_tool_call", "function_call"
            ):
                continue
            stat["tool_calls"] += 1
            source = str(
                payload.get("input") or payload.get("arguments") or ""
            )
            for command in codex_commands(source):
                count_command(command, stat, targets)
                for skill in dict.fromkeys(SKILL_PATH.findall(command)):
                    skills[skill] += 1
                    key = (
                        "skill_project"
                        if skill in PROJECT_SKILLS else "skill_other"
                    )
                    stat[key] += 1

    if project_match and project_match not in workspace:
        return None
    if not stat["tool_calls"]:
        return None
    return {
        "agent": "codex",
        "session": session_id[:8] or os.path.basename(path)[-14:-6],
        "workspace": os.path.basename(workspace),
        "days": sorted(days),
        "counts": dict(stat),
        "skills": dict(skills),
        "targets": dict(targets),
        "reply_words": words,
    }


def scan_session(path: str, since: str | None, until: str | None) -> dict | None:
    stat = collections.Counter(make_gate_requests=0, ensure_gate_requests=0)
    skills = collections.Counter()
    targets = collections.Counter()
    days = set()
    # A reply is turn-final when no further assistant record follows it, so
    # each candidate is held until the next record settles the question.
    pending: str | None = None
    words: list[int] = []

    def settle() -> None:
        nonlocal pending
        if not pending:
            pending = None
            return
        count, furniture = measure(pending)
        words.append(count)
        stat["replies"] += 1
        if count > WORD_LIMIT:
            stat["replies_long"] += 1
        if furniture:
            stat["replies_furniture"] += 1
        pending = None

    try:
        handle = open(path, errors="replace")
    except OSError:
        return None

    with handle:
        for line in handle:
            try:
                record = json.loads(line)
            except ValueError:
                continue
            stamp = (record.get("timestamp") or "")[:10]
            if stamp:
                if since and stamp < since:
                    continue
                if until and stamp > until:
                    continue
                days.add(stamp)
            reply = text_of(record)
            if reply is None:
                settle()
            else:
                pending = reply or None
            for block in blocks(record):
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                name = block.get("name")
                data = block.get("input") or {}
                stat["tool_calls"] += 1
                if name in ("Edit", "Write", "NotebookEdit"):
                    stat["edits"] += 1
                    if SOURCE_EDIT.search(str(data.get("file_path", ""))):
                        stat["source_edits"] += 1
                elif name == "Agent":
                    stat["subagents"] += 1
                elif name == "Skill":
                    skill = data.get("skill", "?")
                    skills[skill] += 1
                    key = "skill_project" if skill in PROJECT_SKILLS else "skill_other"
                    stat[key] += 1
                elif name == "Bash":
                    command = str(data.get("command", ""))
                    count_command(command, stat, targets)

    settle()

    if not stat["tool_calls"]:
        return None
    return {
        "agent": "claude",
        "session": os.path.basename(path)[:8],
        "workspace": os.path.basename(os.path.dirname(path)).split("-x2c-")[-1],
        "days": sorted(days),
        "counts": dict(stat),
        "skills": dict(skills),
        "targets": dict(targets),
        "reply_words": words,
    }


def summarize(sessions: list[dict]) -> dict:
    total = collections.Counter(make_gate_requests=0, ensure_gate_requests=0)
    skills = collections.Counter()
    words: list[int] = []
    for session in sessions:
        total.update(session["counts"])
        skills.update(session["skills"])
        words.extend(session["reply_words"])
    words.sort()

    def ratio(part: str, whole_parts: tuple[str, ...]) -> float | None:
        whole = sum(total[p] for p in whole_parts)
        return round(100 * total[part] / whole, 1) if whole else None

    return {
        "sessions": len(sessions),
        "counts": dict(total),
        "skills": dict(skills.most_common()),
        "reply_words": {
            "median": words[len(words) // 2] if words else None,
            "worst": words[-1] if words else None,
        },
        "rates_percent": {
            "make_alias": ratio("make_alias", ("make_alias", "make_canonical")),
            "push_plain": ratio("push_plain", ("push_plain", "push_refspec")),
            "skill_project": ratio(
                "skill_project", ("skill_project", "skill_other")
            ),
            "replies_long": ratio("replies_long", ("replies",)),
            "replies_furniture": ratio("replies_furniture", ("replies",)),
        },
    }


def transcript_paths(claude_root: str, codex_root: str, agent: str,
                     project_match: str, since: str | None,
                     until: str | None) -> list[tuple[str, str]]:
    paths = []
    if agent in ("all", "claude"):
        pattern = os.path.join(
            os.path.expanduser(claude_root),
            f"*{project_match}*",
            "*.jsonl",
        )
        paths.extend((path, "claude") for path in sorted(glob.glob(pattern)))
    if agent in ("all", "codex"):
        pattern = os.path.join(
            os.path.expanduser(codex_root),
            "*",
            "*",
            "*",
            "rollout-*.jsonl",
        )
        for path in sorted(glob.glob(pattern)):
            name = os.path.basename(path)
            day = name[len("rollout-"):len("rollout-") + 10]
            if since and day < since:
                continue
            if until and day > until:
                continue
            paths.append((path, "codex"))
    return paths


def scan_paths(paths, since, until, project_match):
    sessions = []
    for path, agent in paths:
        if agent == "claude":
            session = scan_session(path, since, until)
        else:
            session = codex_session(path, since, until, project_match)
        if session:
            sessions.append(session)
    return sessions


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root", default=DEFAULT_CLAUDE_ROOT, help="Claude transcript root"
    )
    parser.add_argument("--codex-root", default=DEFAULT_CODEX_ROOT)
    parser.add_argument(
        "--agent", choices=("all", "claude", "codex"), default="all"
    )
    parser.add_argument("--match", default="x2c", help="project directory filter")
    parser.add_argument("--since", help="ISO date, inclusive")
    parser.add_argument("--until", help="ISO date, inclusive")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--per-session", action="store_true")
    parser.add_argument("--by-day", action="store_true")
    args = parser.parse_args()

    paths = transcript_paths(
        args.root,
        args.codex_root,
        args.agent,
        args.match,
        args.since,
        args.until,
    )
    if not paths:
        print(
            "no transcripts matched the requested agent and project",
            file=sys.stderr,
        )
        return 1

    sessions = scan_paths(paths, args.since, args.until, args.match)
    report = summarize(sessions)
    report["by_agent"] = {
        agent: summarize([s for s in sessions if s["agent"] == agent])
        for agent in ("claude", "codex")
        if any(s["agent"] == agent for s in sessions)
    }
    if args.by_day:
        started = collections.defaultdict(list)
        for session in sessions:
            if session["days"]:
                started[session["days"][0]].append(session)
        report["by_day"] = {
            day: summarize(started[day]) for day in sorted(started)
        }
    if args.per_session:
        report["per_session"] = sessions

    if args.json:
        json.dump(report, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return 0

    window = f"{args.since or 'start'}..{args.until or 'now'}"
    print(f"{report['sessions']} sessions, {window}\n")
    print("agents " + ", ".join(
        f"{name} {value['sessions']}"
        for name, value in report["by_agent"].items()
    ) + "\n")
    for name, value in sorted(report["counts"].items()):
        print(f"  {name:26} {value:7}")
    print("\nrates (percent)")
    for name, value in sorted(report["rates_percent"].items()):
        print(f"  {name:26} {'n/a' if value is None else value:>7}")
    reply = report["reply_words"]
    print(f"\nreply prose words: median {reply['median']}, "
          f"worst {reply['worst']}")
    print("\nskills invoked")
    for name, value in report["skills"].items():
        print(f"  {name:34} {value:5}")
    if args.by_day:
        print("\nby day")
        for day, value in report["by_day"].items():
            rates = value["rates_percent"]
            print(
                f"  {day} {value['sessions']:4} sessions "
                f"make_gates={value['counts']['make_gate_requests']} "
                f"ensure_gates={value['counts']['ensure_gate_requests']} "
                f"push={rates['push_plain']}% "
                f"skills={rates['skill_project']}%"
            )
    return 0


if __name__ == "__main__":
    sys.exit(main())
