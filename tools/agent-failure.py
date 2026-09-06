#!/usr/bin/env python3
"""Capture one reported agent failure, with the evidence to study it later.

`tools/harness-metrics.py` counts what agents did. It cannot see what they
said, so a session can score clean on every measure and still end with a claim
that was false when it was made. This captures those: the tail of the
conversation verbatim, the git state it happened in, and the note Gary wrote
when he reported it.

    tools/agent-failure.py capture --note "said the tree was broken; it wasn't"
    tools/agent-failure.py capture --session <uuid> --note "..."
    tools/agent-failure.py list

Evidence lands outside the repository, one directory per incident under
~/.claude/x2c-incidents. Only a short index row belongs in plans/. Nothing in
the build or test process consumes this, and it must never become one.
"""

from __future__ import annotations

import argparse
import collections
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys

CLAUDE_PROJECTS = "~/.claude/projects"
CODEX_SESSIONS = "~/.codex/sessions"
DEFAULT_OUT = "~/.claude/x2c-incidents"
DEFAULT_INDEX = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "plans",
    "agent-failures.md",
)

# Gary's three words for how an agent fails. Do not add a fourth here; leave
# the field blank instead, and let a real pattern earn its own name.
KINDS = ("communication", "compliance", "diligence")

TEXT_BLOCKS = ("text", "input_text")


def clip(text: str, limit: int = 400) -> str:
    text = " ".join(str(text or "").split())
    return text if len(text) <= limit else text[: limit - 3] + "..."


def clip_lines(text: str, lines: int, limit: int = 800) -> str:
    kept = str(text or "").splitlines()[:lines]
    body = "\n".join(kept)
    return body if len(body) <= limit else body[: limit - 3] + "..."


def run(command: list[str], cwd: str) -> str:
    try:
        done = subprocess.run(
            command, cwd=cwd, capture_output=True, text=True, timeout=30
        )
    except (OSError, subprocess.SubprocessError) as error:
        return f"[{error}]"
    return (done.stdout + done.stderr).strip()


def json_lines(path: str):
    with open(path, errors="replace") as handle:
        for line in handle:
            try:
                yield json.loads(line)
            except ValueError:
                continue


# --- transcripts -----------------------------------------------------------


def mangle(path: str) -> str:
    """Claude Code names a project directory after its cwd, / becoming -."""
    return os.path.abspath(path).replace("/", "-")


def find_transcript(session: str | None, workspace: str) -> tuple[str, str]:
    """Return (path, flavor) for the session to capture."""
    root = os.path.expanduser(CLAUDE_PROJECTS)
    session = (session or os.environ.get("CLAUDE_CODE_SESSION_ID")
               or os.environ.get("CONDUCTOR_SESSION_ID"))
    if session:
        direct = os.path.join(root, mangle(workspace), f"{session}.jsonl")
        if os.path.exists(direct):
            return direct, "claude"
        found = glob.glob(os.path.join(root, "*", f"{session}.jsonl"))
        if found:
            return found[0], "claude"
        found = glob.glob(
            os.path.join(os.path.expanduser(CODEX_SESSIONS), "*", "*", "*",
                         f"rollout-*-{session}.jsonl")
        )
        if found:
            return found[0], "codex"
        raise SystemExit(f"no transcript found for session {session}")
    raise SystemExit(
        "no session id: set CLAUDE_CODE_SESSION_ID, or pass --session or "
        "--transcript"
    )


def flavor_of(path: str) -> str:
    for record in json_lines(path):
        return "codex" if "payload" in record else "claude"
    raise SystemExit(f"{path} holds no JSON lines")


def claude_events(path: str, thinking: bool):
    """Yield (role, timestamp, text) in file order. Roles: user, assistant,
    thinking, tool, result."""
    for record in json_lines(path):
        kind = record.get("type")
        stamp = record.get("timestamp") or ""
        message = record.get("message") or {}
        content = message.get("content")
        if kind == "user":
            if isinstance(content, str):
                yield "user", stamp, content
                continue
            for block in content if isinstance(content, list) else []:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "text":
                    yield "user", stamp, block.get("text", "")
                elif block.get("type") == "tool_result":
                    yield "result", stamp, block_text(block.get("content"))
        elif kind == "assistant":
            for block in content if isinstance(content, list) else []:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "text":
                    yield "assistant", stamp, block.get("text", "")
                elif block.get("type") == "thinking" and thinking:
                    yield "thinking", stamp, block.get("thinking", "")
                elif block.get("type") == "tool_use":
                    data = block.get("input") or {}
                    first = next(iter(data.values()), "") if data else ""
                    yield ("tool", stamp,
                           f"{block.get('name')}: {clip(first, 200)}")


def block_text(content) -> str:
    if isinstance(content, str):
        return content
    parts = []
    for block in content if isinstance(content, list) else []:
        if isinstance(block, dict) and block.get("type") in TEXT_BLOCKS:
            parts.append(block.get("text", ""))
    return "\n".join(parts)


def codex_events(path: str, thinking: bool):
    for record in json_lines(path):
        stamp = record.get("timestamp") or ""
        payload = record.get("payload") or {}
        if not isinstance(payload, dict):
            continue
        kind = payload.get("type")
        if kind == "user_message":
            yield "user", stamp, payload.get("message", "")
        elif kind == "agent_message":
            yield "assistant", stamp, payload.get("message", "")
        elif kind == "custom_tool_call":
            yield ("tool", stamp,
                   f"{payload.get('name')}: {clip(payload.get('input'), 200)}")
        elif kind == "function_call":
            yield ("tool", stamp,
                   f"{payload.get('name')}: "
                   f"{clip(payload.get('arguments'), 200)}")
        elif kind in ("custom_tool_call_output", "function_call_output"):
            yield "result", stamp, block_text(payload.get("output"))
        elif kind == "reasoning" and thinking:
            summary = " ".join(
                b.get("text", "") for b in payload.get("summary") or []
                if isinstance(b, dict)
            )
            if summary.strip():
                yield "thinking", stamp, summary


def render(events: list[tuple[str, str, str]], turns: int,
           result_lines: int) -> str:
    """Render the last `turns` turns of the conversation as markdown.

    A turn starts at a user message and runs to the next one, so the count
    matches what a person means by it. User and assistant text is copied
    verbatim; only tool payloads are cut, because what an agent said is the
    entire point of the record.
    """
    spoken = [i for i, (role, _, _) in enumerate(events) if role == "user"]
    start = spoken[-turns] if len(spoken) > turns else 0
    out = []
    heading = {"user": "## User", "assistant": "## Assistant",
               "thinking": "### Thinking"}
    for role, stamp, text in events[start:]:
        if role in heading:
            said = text.rstrip()
            out.append(f"{heading[role]}  <!-- {stamp} -->\n\n{said}\n")
        elif role == "tool":
            out.append(f"    [tool] {text}\n")
        elif role == "result":
            body = clip_lines(text, result_lines)
            indented = "\n".join(
                f"      {line}" for line in body.splitlines()
            )
            out.append(f"{indented}\n" if indented else "")
    return "\n".join(part for part in out if part)


# --- forensics -------------------------------------------------------------


def gone(workspace: str, reason: str) -> str:
    """A Conductor workspace is often deleted before an incident is studied.
    Say so, and fall back to the shared clone the commits are actually in --
    but only when this shell sits beside the missing workspace, since another
    project's repository would answer a different question."""
    root = os.environ.get("CONDUCTOR_ROOT_PATH", "")
    here = os.environ.get("CONDUCTOR_WORKSPACE_PATH", "")
    sibling = here and os.path.dirname(here) == os.path.dirname(workspace)
    shared = root and os.path.exists(os.path.join(root, ".git"))
    if not sibling or not shared:
        return f"{reason}; no shared repository to fall back to.\n"
    log = run(["git", "log", "--oneline", "-20", "origin/dev"], root)
    return (f"{reason}. The commits are in the shared clone; this is that "
            f"repository, not the tree the session ran in.\n\n"
            f"$ git -C {root} log --oneline -20 origin/dev\n{log}\n")


def git_state(workspace: str) -> str:
    if not os.path.exists(workspace):
        return gone(workspace, f"{workspace} no longer exists")
    if not os.path.exists(os.path.join(workspace, ".git")):
        return gone(workspace, f"{workspace} is not a git worktree")
    commands = [
        ["git", "branch", "--show-current"],
        ["git", "rev-parse", "HEAD"],
        ["git", "status", "--porcelain"],
        ["git", "log", "--oneline", "-10"],
        ["git", "diff", "--stat", "origin/dev...HEAD"],
        ["git", "stash", "list"],
    ]
    parts = []
    for command in commands:
        output = run(command, workspace)
        parts.append(f"$ {' '.join(command)}\n{output or '(empty)'}\n")
    gate = os.path.join(workspace, "debug", "gate-state.json")
    if os.path.exists(gate):
        try:
            recorded = json.load(open(gate))
            names = ", ".join(sorted(recorded)) or "(none)"
        except (OSError, ValueError):
            names = "(unreadable)"
        parts.append(f"$ debug/gate-state.json\ngates stamped: {names}\n")
    else:
        parts.append("$ debug/gate-state.json\nabsent\n")
    return "\n".join(parts)


def session_facts(path: str, flavor: str) -> dict:
    facts = {"transcript": path, "flavor": flavor}
    first = last = None
    models, versions, branches = set(), set(), set()
    cwds = collections.Counter()
    count = 0
    for record in json_lines(path):
        count += 1
        stamp = record.get("timestamp")
        if stamp:
            first = first or stamp
            last = stamp
        if flavor == "claude":
            model = (record.get("message") or {}).get("model")
            if model:
                models.add(model)
            for key, sink in (("version", versions), ("gitBranch", branches)):
                if record.get(key):
                    sink.add(record[key])
            if record.get("cwd"):
                cwds[record["cwd"]] += 1
        elif record.get("type") == "session_meta":
            payload = record.get("payload") or {}
            facts["session"] = payload.get("session_id", "")
            versions.add(str(payload.get("cli_version", "")))
            cwds[str(payload.get("cwd", ""))] += 1
            models.add(str(payload.get("model_provider", "")))
    facts.update(
        records=count, first=first or "", last=last or "",
        model=", ".join(sorted(m for m in models if m)),
        agent_version=", ".join(sorted(v for v in versions if v)),
        branch=", ".join(sorted(b for b in branches if b)),
        cwds=[c for c, _ in cwds.most_common() if c],
    )
    facts.setdefault("session", os.path.basename(path).replace(".jsonl", ""))
    subagents = sorted(glob.glob(os.path.join(
        os.path.splitext(path)[0], "subagents", "*.jsonl")))
    facts["subagents"] = subagents
    return facts


# --- capture ---------------------------------------------------------------


def slugify(note: str) -> str:
    words = re.findall(r"[a-z0-9]+", note.lower())
    return "-".join(words[:6]) or "incident"


def capture(args) -> int:
    kinds = [k.strip() for k in (args.kind or "").split(",") if k.strip()]
    if any(k not in KINDS for k in kinds):
        raise SystemExit(f"--kind must be drawn from {', '.join(KINDS)}")
    workspace = os.path.abspath(
        args.workspace
        or os.environ.get("CONDUCTOR_WORKSPACE_PATH")
        or os.getcwd()
    )
    if args.transcript:
        path = os.path.abspath(os.path.expanduser(args.transcript))
        flavor = flavor_of(path)
    else:
        path, flavor = find_transcript(args.session, workspace)

    reader = claude_events if flavor == "claude" else codex_events
    events = list(reader(path, not args.no_thinking))
    if not events:
        raise SystemExit(f"{path} rendered no conversation")

    facts = session_facts(path, flavor)
    # The session says where it ran. Trust that over this shell, which is
    # often a different workspace entirely.
    if not args.workspace and facts["cwds"]:
        workspace = facts["cwds"][0]
    date = (facts["last"] or datetime.date.today().isoformat())[:10]
    slug = args.slug or slugify(args.note)
    out = os.path.join(os.path.expanduser(args.out), f"{date}-{slug}")
    os.makedirs(out, exist_ok=True)

    turns = args.turns
    excerpt = render(events, turns, args.result_lines)
    while len(excerpt.encode()) > args.max_bytes and turns > 2:
        turns -= 2
        excerpt = render(events, turns, args.result_lines)
    cut = ""
    if len(excerpt.encode()) > args.max_bytes:
        dropped = len(excerpt.encode()) - args.max_bytes
        excerpt = excerpt.encode()[dropped:].decode(errors="replace")
        excerpt = excerpt[excerpt.find("\n## ") + 1:] or excerpt
        cut = (f"     The first {dropped} bytes of turn one were dropped to "
               f"stay under --max-bytes.\n")
    header = (
        f"<!-- The last {turns} turns of session {facts['session']}.\n"
        f"     Everything under `## User`, `## Assistant`, and\n"
        f"     `### Thinking` is verbatim. Tool arguments are clipped to\n"
        f"     one line and tool output to {args.result_lines} lines; the\n"
        f"     full record is in transcript.jsonl.\n{cut}-->\n\n"
    )
    write(os.path.join(out, "excerpt.md"), header + excerpt)
    write(os.path.join(out, "git-state.txt"), git_state(workspace))
    if not args.no_raw:
        shutil.copyfile(path, os.path.join(out, "transcript.jsonl"))
    for extra in facts["subagents"]:
        shutil.copyfile(extra, os.path.join(out, os.path.basename(extra)))

    write(os.path.join(out, "incident.md"),
          incident_md(args.note, kinds, facts, workspace, turns, args.no_raw))

    row = (f"| {date} | {' '.join(kinds) or '-'} | {clip(args.note, 90)} | "
           f"`{facts['session'][:8]}` | `{out}` | open |")
    indexed = append_index(os.path.expanduser(args.index), row)
    print(out)
    print(row)
    print(f"{'appended to' if indexed else 'already in'} {args.index}")
    return 0


def incident_md(note: str, kinds: list[str], facts: dict, workspace: str,
                turns: int, no_raw: bool) -> str:
    files = ["`excerpt.md`", "`git-state.txt`"]
    if not no_raw:
        files.append("`transcript.jsonl`")
    return f"""# Reported agent failure

## What was reported

{note}

Kind: {' '.join(kinds) or '(unstated)'}

## What was said

<!--
  Fill this in from excerpt.md. Quote each statement that was objected to
  verbatim, and follow it with one sentence saying what was actually true
  when it was written. Nothing else belongs in this file: no explanation of
  intent, no mitigation, no proposal, no softening. This is evidence.
-->

## Session

| | |
|---|---|
| session | `{facts['session']}` |
| agent | {facts['flavor']} {facts['agent_version'] or ''} |
| model | {facts['model'] or '(unrecorded)'} |
| workspace | `{workspace}` |
| branches worked | {facts['branch'] or '(unrecorded)'} |
| span | {facts['first']} to {facts['last']} |
| records | {facts['records']} |
| transcript | `{facts['transcript']}` |
| subagents | {len(facts['subagents'])} |

Captured: {', '.join(files)}, holding the last {turns} turns.
Git state at capture time is in `git-state.txt`.
"""


def write(path: str, text: str) -> None:
    with open(path, "w") as handle:
        handle.write(text if text.endswith("\n") else text + "\n")


def append_index(path: str, row: str) -> bool:
    """Append one captured incident unless that exact row is already present."""
    try:
        with open(path, encoding="utf-8") as handle:
            current = handle.read()
    except OSError as error:
        raise SystemExit(f"cannot read incident index {path}: {error}")
    if row in current.splitlines():
        return False
    if "| Date | Kind | What was reported |" not in current:
        raise SystemExit(f"{path} is not an agent failure index")
    with open(path, "a", encoding="utf-8") as handle:
        if current and not current.endswith("\n"):
            handle.write("\n")
        handle.write(row + "\n")
    return True


def show(args) -> int:
    root = os.path.expanduser(args.out)
    incidents = sorted(glob.glob(os.path.join(root, "*", "incident.md")))
    if not incidents:
        print(f"no incidents under {root}", file=sys.stderr)
        return 1
    for path in incidents:
        directory = os.path.dirname(path)
        note = ""
        with open(path, errors="replace") as handle:
            lines = handle.read().splitlines()
        for index, line in enumerate(lines):
            if line.startswith("## What was reported"):
                note = " ".join(lines[index + 1: index + 4]).strip()
                break
        print(f"{os.path.basename(directory):48} {clip(note, 78)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    take = sub.add_parser("capture", help="record one incident")
    take.add_argument("--out", default=DEFAULT_OUT)
    take.add_argument(
        "--index", default=DEFAULT_INDEX,
        help="incident index updated by capture",
    )
    take.add_argument("--note", required=True, help="the report, verbatim")
    take.add_argument("--kind",
                      help=f"comma separated, from {', '.join(KINDS)}")
    take.add_argument("--session", help="session id, defaults to this session")
    take.add_argument("--workspace", help="defaults to this workspace")
    take.add_argument("--transcript", help="a transcript file, used as given")
    take.add_argument("--slug", help="directory name, defaults to the note")
    take.add_argument("--turns", type=int, default=12)
    take.add_argument("--result-lines", type=int, default=4)
    take.add_argument("--max-bytes", type=int, default=400_000)
    take.add_argument("--no-thinking", action="store_true")
    take.add_argument("--no-raw", action="store_true",
                      help="skip the full transcript copy")
    take.set_defaults(run=capture)

    listing = sub.add_parser("list", help="every incident on this machine")
    listing.add_argument("--out", default=DEFAULT_OUT)
    listing.set_defaults(run=show)

    args = parser.parse_args()
    return args.run(args)


if __name__ == "__main__":
    sys.exit(main())
