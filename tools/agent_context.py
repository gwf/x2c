#!/usr/bin/env python3
"""Shared worktree delivery context for the Git hook and publication gate."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

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


def publication_blocked(root: str | Path) -> bool:
    root = Path(root)
    context = read_context(root)
    if context is None:
        return root.name.startswith("agent-")
    return context["role"] == "worker" or context["delivery"] != "direct"


def _git(root: Path, *arguments: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *arguments], cwd=root, text=True,
                          capture_output=True, check=False)


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
    if hook.resolve() != expected.resolve():
        raise ValueError("conflicting core.hooksPath; preserve it and arrange "
                         f"the common hook explicitly (effective hook: {hook})")


def set_context(root: str | Path, role: str, delivery: str) -> None:
    if role not in ROLES or delivery not in DELIVERIES:
        raise ValueError("unknown worktree role or delivery mode")
    root = Path(root).resolve()
    _check_hook(root)
    path = root / "debug" / "agent-context.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent,
                                         delete=False) as output:
            temporary = Path(output.name)
            json.dump({"role": role, "delivery": delivery}, output,
                      indent=2, sort_keys=True)
            output.write("\n")
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("set", "blocked"):
        command = sub.add_parser(name)
        command.add_argument("--root", type=Path,
                             default=Path(__file__).resolve().parent.parent)
        if name == "set":
            command.add_argument("--role", choices=sorted(ROLES), required=True)
            command.add_argument("--delivery", choices=sorted(DELIVERIES),
                                 required=True)
    args = parser.parse_args()
    try:
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
