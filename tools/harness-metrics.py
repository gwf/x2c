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
    tools/harness-metrics.py --by-day        # first active UTC day in window

Discovery includes archives and nested workers. Date-only windows retain
inclusive UTC days; timezone-aware timestamps select [since, until).
Counts describe observed invocations, not execution or wasted work. Edit
requests are observable through explicit edit tools; arbitrary shell edits
are unavailable. Final replies are deduplicated across paired record forms.
Coverage and unavailable fields are reported separately for each platform.
Transcripts are private. Keep the output aggregate and keep the raw sessions
out of the repository.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import glob
import hashlib
import heapq
import json
import os
import re
import sys
from pathlib import Path

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
    "benchmarks": "bm-all", "book": "doc-build",
    "sanitizer-unittest": "verify-sanitize",
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

def project_skills(root=None):
    root = root or Path(__file__).resolve().parents[1] / "agents/skills"
    names = set()
    for path in Path(root).glob("*/SKILL.md"):
        text = path.read_text(encoding="utf-8")
        header = text.split("---", 2)
        if len(header) == 3 and not header[0].strip():
            match = re.search(r"^name:\s*(.+?)\s*$", header[1], re.M)
            if match:
                names.add(match.group(1).strip("\"'"))
    return names


PROJECT_SKILLS = project_skills()

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


def timestamp(value):
    try:
        result = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if result.tzinfo is None:
            return None
        return result.astimezone(dt.timezone.utc)
    except ValueError:
        return None


def boundary(value, upper=False):
    if not value:
        return None
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        result = dt.datetime.fromisoformat(value).replace(tzinfo=dt.timezone.utc)
        return result + dt.timedelta(days=1) if upper else result
    result = timestamp(value)
    if result is None:
        raise ValueError("use a UTC date or a timezone-aware ISO timestamp")
    return result


def in_window(record, since, until):
    payload = record.get("payload") or {}
    value = timestamp(record.get("timestamp") or payload.get("timestamp"))
    return value is not None and (since is None or value >= since) and (
        until is None or value < until)


def records(path, coverage=None):
    try:
        with open(path, errors="replace") as handle:
            for line in handle:
                try:
                    record = json.loads(line)
                    if isinstance(record, dict):
                        yield record
                    elif coverage is not None:
                        coverage["malformed_records"] += 1
                except ValueError:
                    if coverage is not None:
                        coverage["malformed_records"] += 1
    except OSError:
        if coverage is not None:
            coverage["unreadable_files"] += 1


def identity(path, agent):
    # The first metadata belongs to this file; later metadata can be replayed.
    for record in records(path):
        if agent == "codex" and record.get("type") == "session_meta":
            payload = record.get("payload") or {}
            return (str(payload.get("id") or payload.get("session_id") or path),
                    str(payload.get("cwd") or ""))
        if agent == "claude" and record.get("sessionId"):
            session_id = str(record["sessionId"])
            worker = record.get("agentId")
            if not worker and "subagents" in Path(path).parts:
                worker = Path(path).stem
            if worker:
                session_id += ":" + str(worker)
            return session_id, str(record.get("cwd") or "")
    return str(Path(path).resolve()), str(Path(path).parent)


def merged_records(paths, coverage):
    def ordered(path):
        for index, record in enumerate(records(path, coverage)):
            payload = record.get("payload") or {}
            stamp = timestamp(record.get("timestamp") or payload.get("timestamp"))
            yield (stamp or dt.datetime.min.replace(tzinfo=dt.timezone.utc),
                   index, record)

    seen = set()
    streams = [ordered(path) for path in paths]
    for _, _, record in heapq.merge(*streams, key=lambda row: row[:2]):
        payload = record.get("payload") or {}
        event_id = record.get("uuid") or (
            payload.get("id") if record.get("type") == "response_item" else None)
        represented = ((record.get("type"), event_id) if event_id else
                       {k: v for k, v in record.items() if k != "ordinal"})
        key = hashlib.sha256(json.dumps(
            represented, sort_keys=True, separators=(",", ":"),
        ).encode()).digest()
        if key in seen:
            coverage["duplicate_records"] += 1
            continue
        seen.add(key)
        coverage["records"] += 1
        yield record


def session_records(paths, agent, session_id, workspace, since, until,
                    project_match, coverage):
    if project_match and project_match not in workspace and not (
        agent == "claude" and any(project_match in path for path in paths)
    ):
        coverage["project_excluded_sessions"] += 1
        return None
    stat = collections.Counter(make_gate_requests=0, ensure_gate_requests=0)
    skills, targets = collections.Counter(), collections.Counter()
    days, words, calls, patch_calls = set(), [], set(), set()
    last_reply = None
    start_counts = collections.Counter()
    pending = None
    active = False
    supported = set()
    born = None
    if agent == "codex":
        for record in records(paths[0]):
            if record.get("type") == "session_meta":
                born = timestamp((record.get("payload") or {}).get("timestamp")
                                 or record.get("timestamp"))
                break

    def settle():
        nonlocal pending
        if pending:
            reply, selected = pending
            if selected and reply:
                add_reply(reply, stat, words)
        pending = None

    def skill_count(source):
        for skill in dict.fromkeys(SKILL_PATH.findall(source)):
            skills[skill] += 1
            stat["skill_project" if skill in PROJECT_SKILLS else "skill_other"] += 1

    for record in merged_records(paths, coverage):
        stamp = timestamp(record.get("timestamp"))
        if born and stamp and stamp < born:
            coverage["replayed_records"] += 1
            continue
        selected = in_window(record, since, until)
        payload = record.get("payload") or {}
        kind = payload.get("type")
        if agent == "claude":
            reply = text_of(record)
            if reply is None:
                settle()
            else:
                pending = (reply, selected)
        if not selected:
            continue
        coverage["records_in_window"] += 1
        value = timestamp(record.get("timestamp") or payload.get("timestamp"))
        days.add(value.date().isoformat())
        if agent == "codex":
            if kind in ("task_started", "user_message"):
                last_reply = None
                start_counts.clear()
            final = (kind == "message" and payload.get("role") == "assistant"
                     and (payload.get("phase") == "final_answer"
                          or payload.get("channel") == "final"))
            legacy = kind == "agent_message" and (
                payload.get("phase") == "final_answer"
                or payload.get("channel") == "final")
            if final or legacy:
                reply = ("\n".join(b.get("text", "")
                         for b in payload.get("content", [])
                         if isinstance(b, dict)) if final else
                         str(payload.get("message") or "")).strip()
                if reply:
                    # Paired legacy events and response items represent one reply.
                    representation = "message" if final else "event"
                    opposite = "event" if final else "message"
                    same_reply = (last_reply and last_reply[0] == reply
                                  and last_reply[1] == opposite)
                    if not same_reply:
                        add_reply(reply, stat, words)
                    last_reply = None if same_reply else (reply, representation)
                supported.add("replies")
                active = True
            if record.get("type") == "event_msg":
                if kind == "patch_apply_end" and payload.get("success"):
                    call_id = payload.get("call_id")
                    if call_id and call_id in patch_calls:
                        continue
                    patch_calls.add(call_id)
                    changed = payload.get("changes") or {}
                    stat["edits"] += bool(changed)
                    stat["source_edits"] += any(
                        SOURCE_EDIT.search(str(p)) for p in changed)
                    supported.update(("edits", "source_edits"))
                    active = True
                elif kind == "sub_agent_activity" and payload.get("kind") == "started":
                    supported.add("subagents")
                    start_counts["event"] += 1
                    stat["subagents"] += start_counts["event"] > start_counts["tool"]
                    active = True
                continue
            if kind == "message" and payload.get("role") == "user":
                last_reply = None
                start_counts.clear()
            if (kind == "message" and payload.get("role") == "assistant"
                    and not final):
                last_reply = None
            if record.get("type") != "response_item":
                continue
            if kind == "message" and payload.get("role") in ("user", "assistant"):
                active = True
                supported.add("replies")
            if kind not in ("custom_tool_call", "function_call"):
                continue
            last_reply = None
            call_id = payload.get("call_id") or payload.get("id")
            if call_id and call_id in calls:
                continue
            if call_id:
                calls.add(call_id)
            name = str(payload.get("name") or "")
            source = str(payload.get("input") or payload.get("arguments") or "")
            try:
                data = json.loads(source)
            except ValueError:
                data = {}
            commands = list(codex_commands(source))
            if isinstance(data, dict) and data.get("cmd"):
                commands = [str(data["cmd"])]
            for command in commands:
                count_command(command, stat, targets)
                skill_count(command)
            patch = name.endswith("apply_patch") or "tools.apply_patch(" in source
            if patch:
                if call_id not in patch_calls:
                    stat["edits"] += 1
                    changed = re.findall(
                        r"\*\*\* (?:Update|Add|Delete) File:\s*(\S+)", source)
                    stat["source_edits"] += any(
                        SOURCE_EDIT.search(path) for path in changed)
                    patch_calls.add(call_id)
                supported.update(("edits", "source_edits"))
            if name.endswith("spawn_agent"):
                start_counts["tool"] += 1
                stat["subagents"] += start_counts["tool"] > start_counts["event"]
                supported.add("subagents")
            supported.update(("tool_calls", "commands", "skills"))
            stat["tool_calls"] += 1
            active = True
        else:
            if record.get("type") in ("user", "assistant"):
                active = True
                supported.update(("replies", "tool_calls", "edits", "source_edits",
                                  "subagents", "commands", "skills"))
            for block in blocks(record):
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                call_id = block.get("id")
                if call_id and call_id in calls:
                    continue
                if call_id:
                    calls.add(call_id)
                name, data = block.get("name"), block.get("input") or {}
                stat["tool_calls"] += 1
                if name in ("Edit", "Write", "NotebookEdit"):
                    stat["edits"] += 1
                    stat["source_edits"] += bool(SOURCE_EDIT.search(
                        str(data.get("file_path", ""))))
                elif name in ("Agent", "Task"):
                    stat["subagents"] += 1
                elif name == "Skill":
                    skill = data.get("skill", "?")
                    skills[skill] += 1
                    stat["skill_project" if skill in PROJECT_SKILLS else "skill_other"] += 1
                elif name == "Bash":
                    count_command(str(data.get("command", "")), stat, targets)
    settle()
    if not active:
        coverage["inactive_sessions"] += 1
        return None
    return {
        "agent": agent, "session": session_id, "workspace": os.path.basename(workspace),
        "days": sorted(days), "counts": dict(stat), "skills": dict(skills),
        "targets": dict(targets), "reply_words": words,
        "available": sorted(supported),
    }


def codex_session(path, since, until, project_match):
    session_id, workspace = identity(path, "codex")
    return session_records([path], "codex", session_id, workspace,
                           boundary(since), boundary(until, True), project_match,
                           collections.Counter())


def scan_session(path, since, until):
    session_id, workspace = identity(path, "claude")
    return session_records([path], "claude", session_id, workspace,
                           boundary(since), boundary(until, True), "",
                           collections.Counter())


def summarize(sessions: list[dict]) -> dict:
    total = collections.Counter(make_gate_requests=0, ensure_gate_requests=0)
    skills = collections.Counter()
    words: list[int] = []
    for session in sessions:
        total.update(session["counts"])
        skills.update(session["skills"])
        words.extend(session["reply_words"])
    words.sort()
    fields = {name: name for name in
              ("replies", "edits", "source_edits", "subagents", "tool_calls")}
    fields.update({name: "commands" for name in
                   ("make_gate_requests", "ensure_gate_requests")})
    unavailable = sorted(field for field, source in fields.items()
                         if not any(source in s.get("available", [])
                                    for s in sessions))
    for field in fields.keys() - set(unavailable):
        total.setdefault(field, 0)

    def ratio(part: str, whole_parts: tuple[str, ...]) -> float | None:
        whole = sum(total[p] for p in whole_parts)
        return round(100 * total[part] / whole, 1) if whole else None

    return {
        "sessions": len(sessions),
        "unavailable_fields": unavailable + ["executed_checks", "wasted_time",
                                              "shell_edits"],
        "field_coverage": {
            field: sum(fields[field] in s.get("available", []) for s in sessions)
            for field in sorted(fields)
        },
        "counts": {name: value for name, value in total.items()
                   if name not in unavailable},
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


def transcript_paths(claude_root, codex_root, agent, project_match,
                     since, until, codex_archive_root=None):
    paths = []
    if agent in ("all", "claude"):
        root = os.path.expanduser(claude_root)
        paths.extend((path, "claude") for path in
                     sorted(glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True)))
    if agent in ("all", "codex"):
        root = Path(os.path.expanduser(codex_root))
        archive = (Path(os.path.expanduser(codex_archive_root))
                   if codex_archive_root else root.parent / "archived_sessions")
        for directory in dict.fromkeys((root, archive)):
            paths.extend((str(path), "codex") for path in
                         sorted(directory.rglob("*.jsonl")))
    return list(dict.fromkeys(paths))


def scan_paths(paths, since, until, project_match, coverage=None):
    lower, upper = boundary(since), boundary(until, True)
    if lower and upper and lower >= upper:
        raise ValueError("--since must precede the exclusive --until boundary")
    coverage = coverage if coverage is not None else {}
    groups = collections.defaultdict(list)
    workspaces = {}
    for path, agent in paths:
        stat = coverage.setdefault(agent, collections.Counter())
        stat["files"] += 1
        if "archived_sessions" in Path(path).parts:
            stat["archive_files"] += 1
        if "subagents" in Path(path).parts:
            stat["nested_worker_files"] += 1
        session_id, workspace = identity(path, agent)
        key = (agent, session_id)
        groups[key].append(path)
        workspaces.setdefault(key, workspace)
    sessions = []
    for (agent, session_id), group in groups.items():
        stat = coverage[agent]
        stat["session_identities"] += 1
        stat["complementary_files"] += len(group) - 1
        session = session_records(group, agent, session_id,
                                  workspaces[(agent, session_id)], lower, upper,
                                  project_match, stat)
        if session:
            stat["active_sessions"] += 1
            sessions.append(session)
    return sessions


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root", default=DEFAULT_CLAUDE_ROOT, help="terminal transcript root"
    )
    parser.add_argument("--codex-root", default=DEFAULT_CODEX_ROOT)
    parser.add_argument("--codex-archive-root", help="defaults to the sibling archive")
    parser.add_argument(
        "--agent", choices=("all", "claude", "codex"), default="all"
    )
    parser.add_argument("--match", default="x2c", help="project directory filter")
    parser.add_argument("--since", help="inclusive UTC date or timezone-aware ISO timestamp")
    parser.add_argument(
        "--until", help="inclusive UTC date or exclusive timezone-aware ISO timestamp")
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
        args.codex_archive_root,
    )
    if not paths:
        print(
            "no transcripts matched the requested agent and project",
            file=sys.stderr,
        )
        return 1

    coverage = {}
    try:
        sessions = scan_paths(paths, args.since, args.until, args.match, coverage)
    except ValueError as error:
        parser.error(str(error))
    report = summarize(sessions)
    report["by_agent"] = {}
    for agent, counts in coverage.items():
        summary = summarize([s for s in sessions if s["agent"] == agent])
        summary["coverage"] = dict(counts)
        report["by_agent"][agent] = summary
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
    print("coverage " + ", ".join(
        f"{name}: {value['coverage']['files']} files, "
        f"{value['coverage'].get('records_in_window', 0)} records in window"
        for name, value in report["by_agent"].items()
    ))
    print("unavailable fields: " + ", ".join(report["unavailable_fields"]))
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
                f"make_gates={value['counts'].get('make_gate_requests', 'n/a')} "
                f"ensure_gates={value['counts'].get('ensure_gate_requests', 'n/a')} "
                f"push={rates['push_plain']}% "
                f"skills={rates['skill_project']}%"
            )
    return 0


if __name__ == "__main__":
    sys.exit(main())
