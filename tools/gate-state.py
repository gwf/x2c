#!/usr/bin/env python3
"""Reuse or produce publication proof for the exact current tree.

`AGENTS.md` says green evidence belongs to the exact relevant tree, and that a
commit, review, push, or elapsed time does not invalidate it. Deciding that by
hand is where the rule fails in practice, so this answers it exactly instead.

    tools/gate-state.py ensure agent-pr-check

`check` prints `valid` only when every tracked and untracked non-ignored file
has the same content, type, and executable permissions as the tree that passed,
with the same effective build configuration and tools. Anything else is
`stale`, and it names what moved.
It exits 0 for valid and 1 for stale, so a shell can branch on it.

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
import os
import pathlib
import shlex
import shutil
import stat
import subprocess
import sys
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
STATE = ROOT / "debug" / "gate-state.json"
GATES = {"agent-pr-check", "doc-check"}


def git(*args: str) -> str:
    out = subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, check=True
    )
    return out.stdout


# The root Makefile owns defaults and precedence. Child Makefiles derive their
# flags from these inputs; their definitions are already in the file digest.
# Search/SDK variables also affect native tools without appearing in argv.
TOOL_ENV_VARIABLES = (
    "PATH CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH COMPILER_PATH "
    "GCC_EXEC_PREFIX SDKROOT DEVELOPER_DIR TOOLCHAINS MACOSX_DEPLOYMENT_TARGET "
    "LD_LIBRARY_PATH DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH"
).split()
CONFIG_VARIABLES = (
    "MAKE CC AR ARFLAGS RANLIB SHELL BUILD_MODE BUILD_LTO BUILD_CFLAGS "
    "BUILD_LDFLAGS BUILD_JOBS CFLAGS CPPFLAGS LDFLAGS LDLIBS EXTRA_CFLAGS "
    "FLAGS X2C_FLAGS X2CFLAGS X2C X2C_CC X2C_AR STAGE0_X2C JOBS"
).split() + TOOL_ENV_VARIABLES


def make_configuration() -> dict[str, str]:
    """Read expanded values without executing any build target or recipe.

    A second Makefile uses info so values never cross a shell quoting
    boundary. Command-line overrides are included even when a child target
    is their only consumer. The random framing lets us
    reject unsupported multiline values instead of recording partial input.
    """
    marker = "x2c-gate-" + uuid.uuid4().hex
    probe = "\n".join([
        f"$(info {marker}:begin)",
        *[f"$(info {marker}:{name}=$({name}))"
          for name in [*CONFIG_VARIABLES, "MAKEFLAGS"]],
        "$(foreach v,$(.VARIABLES),"
        "$(if $(findstring command line,$(origin $(v))),"
        f"$(info {marker}:override:$(v)=$($(v)))))",
        f"$(info {marker}:end)",
        ".PHONY: x2c-gate-inspect",
        "x2c-gate-inspect: ;",
    ])
    out = subprocess.run(
        ["make", "--no-print-directory", "-f", "Makefile", "-f", "-",
         "x2c-gate-inspect"], cwd=ROOT, input=probe, capture_output=True,
        text=True, check=True,
    )
    lines = out.stdout.splitlines()
    start = lines.index(f"{marker}:begin")
    end = lines.index(f"{marker}:end", start + 1)
    values = {}
    for line in lines[start + 1:end]:
        if not line.startswith(marker + ":") or "=" not in line:
            raise ValueError("cannot inspect multiline Make configuration")
        name, value = line[len(marker) + 1:].split("=", 1)
        values[name] = value
    flags = shlex.split(values.pop("MAKEFLAGS"))
    modes = []
    for flag in flags:
        if flag == "--":
            break
        if (flag in {"--just-print", "--dry-run", "--recon", "--question",
                     "--touch", "--ignore-errors"} or
                flag.startswith(("--old-file", "--assume-old")) or
                (not flag.startswith("--") and "=" not in flag and
                 any(letter in flag for letter in "inqto"))):
            raise ValueError("Make mode can skip failures or required gate work")
        if not flag.startswith(("--jobserver-fds=", "--jobserver-auth=")):
            modes.append(flag)
    values["MAKEFLAGS"] = " ".join(modes)
    return values


def tool_identity(
    command: str, path: str, compiler: bool = False, environment: dict | None = None,
) -> dict:
    """Identify a single native executable; opaque wrapper commands fail closed."""
    arguments = shlex.split(command)
    if len(arguments) != 1:
        raise ValueError(f"cannot inspect wrapped tool command: {command!r}")
    name = arguments[0]
    if "/" in name:
        name = str(ROOT / name)
    found = shutil.which(name, path=path)
    if not found:
        raise ValueError(f"cannot find build tool: {command!r}")
    executable = pathlib.Path(found).resolve(strict=True)
    if (sys.platform == "darwin" and executable.parent == pathlib.Path("/usr/bin")
            and executable.name in {"cc", "clang", "gcc", "ar", "ranlib", "make"}):
        # These are launchers for the selected developer directory. Their own
        # bytes do not identify the compiler or archiver that a gate will use.
        selected = subprocess.run(
            ["/usr/bin/xcrun", "--find", executable.name], cwd=ROOT,
            capture_output=True, text=True, check=True, env=environment,
        )
        if not selected.stdout.strip():
            raise ValueError(f"cannot resolve Apple build tool: {command!r}")
        executable = pathlib.Path(selected.stdout.strip()).resolve(strict=True)
    data = executable.read_bytes()
    if data.startswith(b"#!"):
        raise ValueError(f"cannot inspect script tool wrapper: {command!r}")
    identity = {
        "path": str(executable),
        "sha256": hashlib.sha256(data).hexdigest(),
    }
    if compiler:
        out = subprocess.run(
            [str(executable), "--version"], cwd=ROOT, capture_output=True,
            text=True, check=True, env=environment,
        )
        if not out.stdout.strip():
            raise ValueError(f"cannot identify compiler: {command!r}")
        identity["version"] = out.stdout.strip()
    return identity


def build_configuration() -> dict:
    values = make_configuration()
    environment = os.environ.copy()
    for name in TOOL_ENV_VARIABLES:
        if values[name]:
            environment[name] = values[name]
        else:
            environment.pop(name, None)
    commands = {"MAKE": values["MAKE"], "CC": values["CC"], "AR": values["AR"]}
    for name in ("RANLIB", "X2C", "X2C_CC", "X2C_AR", "STAGE0_X2C"):
        if values[name]:
            commands[name] = values[name]
    # The default stage-0 compiler is a gate output. Its sources and bootstrap
    # inputs belong to the tree digest; only an explicit replacement is a tool
    # input whose contents need recording here.
    if commands.get("STAGE0_X2C") == "./builds/0/x2c":
        del commands["STAGE0_X2C"]
    identities = {"make": tool_identity("make", os.environ.get("PATH", os.defpath))}
    for name, command in commands.items():
        identities[name] = tool_identity(
            command, values["PATH"], name in {"CC", "X2C_CC"}, environment,
        )
    return {"values": values, "tools": identities}


# Version 5 captures effective Make configuration and executable identities.
# Older records lack those inputs and must be validated once again.
FORMAT = 5


def content_hash(rel: str, mode: int) -> str:
    """Git's blob hash for a path's current bytes.

    This must be git's own blob hash and not a plain digest of the bytes,
    because `tree_content` reads the index blob hash for every unmodified
    tracked file. Using the same hash makes the result independent of whether
    a file is staged.
    """
    path = ROOT / rel
    data = (os.fsencode(os.readlink(path)) if stat.S_ISLNK(mode)
            else path.read_bytes())
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
    identical files mean an identical build no matter where they are recorded.
    Ignored paths are excluded, so scratch under `debug/` is irrelevant.

    Tracked files use the index blob hash, which costs no file reads. Only
    paths whose working tree differs from the index, plus untracked ones, are
    hashed directly. Metadata comes from lstat even when Git ignores mode
    changes. Missing paths are omitted before and after staging their deletion.
    """
    index: dict[str, str] = {}
    for record in zsplit(git("ls-files", "-s", "-z")):
        meta, _, path = record.partition("\t")
        fields = meta.split()
        if path and len(fields) >= 2:
            index[path] = fields[1][:16]
    changed = set(zsplit(git("diff", "--name-only", "-z")))
    untracked = zsplit(git("ls-files", "--others", "--exclude-standard", "-z"))
    entries: dict[str, str] = {}
    for path in index.keys() | set(untracked):
        try:
            mode = (ROOT / path).lstat().st_mode
        except (FileNotFoundError, NotADirectoryError):
            continue
        if stat.S_ISDIR(mode):
            continue
        if not (stat.S_ISREG(mode) or stat.S_ISLNK(mode)):
            raise ValueError(f"unsupported file type: {path}")
        blob = (index[path] if path in index and path not in changed
                else content_hash(path, mode))
        entries[path] = f"{stat.S_IFMT(mode):o}:{mode & 0o111:o}:{blob}"
    return entries


def digest() -> dict:
    return {
        "version": FORMAT,
        "files": tree_content(),
        "configuration": build_configuration(),
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
    if old.get("configuration") != new["configuration"]:
        reasons.append("build configuration or tools changed")
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
    try:
        if args.command == "record":
            return cmd_record(args.gate)
        if args.command == "check":
            return cmd_check(args.gate)
        return cmd_ensure(args.gate)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        detail = (error.stderr.strip() if isinstance(
            error, subprocess.CalledProcessError) else str(error))
        print(f"cannot inspect current tree: {detail}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
