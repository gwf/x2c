#!/usr/bin/env python3
"""Shared worktree delivery context for the Git hook and publication gate.

The delivery tools also share their Git runner, atomic JSON writes, process
locks, and script loading from here.
"""

from __future__ import annotations

import argparse
import fcntl
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

ROLES = {"individual", "orchestrator", "integrator", "worker"}
DELIVERIES = {"direct", "pr", "private"}


def read_context(root: str | Path) -> dict | None:
    path = Path(root) / "debug" / "agent-context.json"
    try:
        context = json.loads(path.read_text())
    except FileNotFoundError:
        if path.is_symlink():
            raise ValueError(f"malformed delivery context: {path}")
        return None
    except (ValueError, UnicodeError) as error:
        raise ValueError(f"malformed delivery context: {path}") from error
    if (not isinstance(context, dict) or
            set(context) != {"role", "delivery"} or
            not isinstance(context["role"], str) or
            context["role"] not in ROLES or
            not isinstance(context["delivery"], str) or
            context["delivery"] not in DELIVERIES):
        raise ValueError(f"malformed delivery context: {path}")
    return context


def push_policy(root: str | Path) -> str:
    """Which branches this worktree may push: `all`, `work`, or `none`.

    A worker hands its commits to its orchestrator, so it pushes nothing.
    Other contexts that do not deliver directly push only work branches.
    """
    root = Path(root)
    context = read_context(root)
    if context is None:
        return "work" if root.name.startswith("agent-") else "all"
    if context["role"] == "worker":
        return "none"
    return "all" if context["delivery"] == "direct" else "work"


def publication_blocked(root: str | Path) -> bool:
    return push_policy(root) != "all"


def _git(root: Path | None, *arguments: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *arguments], cwd=root, text=True,
                          capture_output=True, check=False)


def git(*arguments: str, root: str | Path | None = None) -> str:
    """Returns Git's standard output, run in `root` or the current directory.
    A failure raises ValueError with Git's message."""
    result = _git(root, *arguments)
    if result.returncode:
        raise ValueError(result.stderr.strip() or "git command failed")
    return result.stdout


def write_json(path: str | Path, value: object, sort_keys: bool = True):
    """Replaces `path` with indented JSON in one rename, so a reader sees the
    old document or the new one."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp-" + uuid.uuid4().hex)
    try:
        temporary.write_text(json.dumps(value, indent=2, sort_keys=sort_keys) +
                             "\n", encoding="utf-8")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def pid_lock(path: str | Path, busy: str):
    """Locks `path` without waiting and records this process's pid in it.
    Returns the open file, which holds the lock until it closes. A held lock
    raises ValueError with `busy` and the holder's pid."""
    stream = Path(path).open("a+")
    try:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            stream.seek(0)
            holder = stream.read().strip() or "unknown"
            raise ValueError(f"{busy} (pid {holder})") from error
        stream.seek(0)
        stream.truncate()
        stream.write(f"{os.getpid()}\n")
        stream.flush()
    except BaseException:
        stream.close()
        raise
    return stream


def load_script(path: str | Path, name: str):
    """Loads a script whose file name is not a module name, such as
    `gate-state.py` or `land-dev`, as module `name`."""
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _check_hook(root: Path) -> None:
    expected = root / "tools" / "hooks" / "pre-push"
    if not expected.is_file() or not os.access(expected, os.X_OK):
        raise ValueError(f"common pre-push hook is missing or not executable: "
                         f"{expected}")
    configured = _git(root, "config", "--get", "core.hooksPath")
    if configured.returncode == 1:
        installed = _git(root, "config", "--local", "core.hooksPath", "tools/hooks")
        if installed.returncode:
            raise ValueError("cannot configure common pre-push hook: " +
                             installed.stderr.strip())
    elif configured.returncode:
        raise ValueError("cannot read core.hooksPath: " + configured.stderr.strip())
    effective = _git(root, "rev-parse", "--git-path", "hooks/pre-push")
    if effective.returncode:
        raise ValueError("cannot inspect effective pre-push hook: " +
                         effective.stderr.strip())
    hook = Path(effective.stdout.strip())
    if not hook.is_absolute():
        hook = root / hook
    if (not hook.is_file() or not os.access(hook, os.X_OK) or
            hook.read_bytes() != expected.read_bytes()):
        raise ValueError("conflicting core.hooksPath; preserve it and arrange "
                         f"the common hook explicitly (effective hook: {hook})")


def set_context(root: str | Path, role: str, delivery: str) -> None:
    if role not in ROLES or delivery not in DELIVERIES:
        raise ValueError("unknown worktree role or delivery mode")
    if role == "worker" and delivery != "private":
        raise ValueError("a worker hands its work to its orchestrator; "
                         "use --delivery private")
    root = Path(root).resolve()
    _check_hook(root)
    write_json(root / "debug" / "agent-context.json",
               {"role": role, "delivery": delivery})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    # A hook path that names another checkout's hook can run a copy that still
    # asks `blocked`.
    for name in ("set", "pushes", "blocked"):
        command = sub.add_parser(name)
        command.add_argument("--root", type=Path,
                             default=Path(__file__).resolve().parent.parent)
        if name == "set":
            command.add_argument("--role", choices=sorted(ROLES), required=True)
            command.add_argument("--delivery", choices=sorted(DELIVERIES),
                                 required=True)
    args = parser.parse_args()
    try:
        if args.command == "pushes":
            print(push_policy(args.root))
            return 0
        if args.command == "blocked":
            return 0 if publication_blocked(args.root) else 1
        set_context(args.root, args.role, args.delivery)
        print(f"context: {args.role}/{args.delivery}; common hook verified")
        return 0
    except (OSError, ValueError) as error:
        print(f"agent-context: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
