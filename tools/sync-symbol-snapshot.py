#!/usr/bin/env python3
"""Refresh the tracked symbol snapshot only when its real inputs changed."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


FORMAT = 1
ENVIRONMENT_KEYS = (
    "CC",
    "CPP",
    "CPATH",
    "C_INCLUDE_PATH",
    "SDKROOT",
    "MACOSX_DEPLOYMENT_TARGET",
)


def hash_file(digest, root: Path, path: Path) -> None:
    digest.update(str(path.relative_to(root)).encode("utf-8"))
    digest.update(b"\0")
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    digest.update(b"\0")


def hash_contents(digest, path: Path) -> None:
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    digest.update(b"\0")


def input_paths(root: Path) -> list[Path]:
    paths = {
        root / "etc" / "symbol-source.x",
        root / "lib" / "Makefile",
    }
    paths.update((root / "lib").glob("*.x"))
    paths.update((root / "lib").glob("*.xmacro"))
    paths.update((root / "etc").glob("*.xmacro"))
    paths.update(
        path
        for path in (root / "etc").glob("*.xlisp")
        if path.name not in {"symbols.xlisp", "header-symbols.xlisp"}
    )
    return sorted(path for path in paths if path.is_file())


def fingerprint(root: Path, compiler: Path) -> str:
    digest = hashlib.sha256()
    digest.update(f"symbol-snapshot-state {FORMAT}\0".encode("ascii"))
    digest.update(b"tool\0")
    hash_contents(digest, Path(__file__).resolve())
    digest.update(b"compiler\0")
    hash_contents(digest, compiler)
    for path in input_paths(root):
        hash_file(digest, root, path)
    for name in ENVIRONMENT_KEYS:
        digest.update(name.encode("ascii"))
        digest.update(b"=")
        digest.update(os.environ.get(name, "").encode("utf-8"))
        digest.update(b"\0")
    return digest.hexdigest()


def content_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_state(path: Path) -> dict[str, object] | None:
    try:
        value = json.loads(path.read_text(encoding="ascii"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None
    return value if isinstance(value, dict) else None


def atomic_write(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(content)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def write_state(path: Path, key: str, artifact: Path) -> None:
    value = {
        "format": FORMAT,
        "fingerprint": key,
        "artifact": content_hash(artifact),
    }
    atomic_write(
        path,
        (json.dumps(value, sort_keys=True) + "\n").encode("ascii"),
    )


def current(state: dict[str, object] | None, key: str, artifact: Path) -> bool:
    return bool(
        state
        and state.get("format") == FORMAT
        and state.get("fingerprint") == key
        and artifact.is_file()
        and state.get("artifact") == content_hash(artifact)
    )


def dump_snapshot(root: Path, compiler: Path) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        [
            str(compiler),
            "translate",
            "--live-symbols",
            "--dump-symbol-snapshot",
            "etc/symbol-source.x",
        ],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path)
    parser.add_argument("--compiler", required=True, type=Path)
    parser.add_argument("--fallback", type=Path)
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--state", type=Path)
    parser.add_argument("--changed", type=Path)
    return parser.parse_args()


def resolve(root: Path, path: Path) -> Path:
    return path if path.is_absolute() else root / path


def main() -> int:
    arguments = parse_arguments()
    root = (arguments.root or Path(__file__).resolve().parents[1]).resolve()
    artifact = resolve(root, arguments.artifact or Path("etc/symbols.xlisp"))
    state_path = resolve(
        root, arguments.state or Path("builds/.symbol-snapshot-state")
    )
    changed = resolve(
        root, arguments.changed or Path("builds/.symbol-snapshot-changed")
    )
    candidates = [arguments.compiler]
    if arguments.fallback and arguments.fallback != arguments.compiler:
        candidates.append(arguments.fallback)

    failures: list[tuple[Path, subprocess.CompletedProcess[bytes]]] = []
    for candidate in candidates:
        compiler = resolve(root, candidate)
        if not compiler.is_file() or not os.access(compiler, os.X_OK):
            continue
        key = fingerprint(root, compiler)
        if current(read_state(state_path), key, artifact):
            changed.unlink(missing_ok=True)
            return 0
        result = dump_snapshot(root, compiler)
        if result.returncode:
            failures.append((compiler, result))
            continue
        if not result.stdout.startswith(b"(snapshot "):
            print(
                f"{compiler}: symbol snapshot output has no snapshot header",
                file=sys.stderr,
            )
            return 1
        previous = artifact.read_bytes() if artifact.is_file() else None
        if previous != result.stdout:
            atomic_write(artifact, result.stdout)
            atomic_write(changed, b"changed\n")
            print("Refreshing etc/symbols.xlisp")
        else:
            changed.unlink(missing_ok=True)
        write_state(state_path, key, artifact)
        if failures:
            failed = failures[0][0]
            print(
                f"symbol snapshot: {failed} failed; used {compiler}",
                file=sys.stderr,
            )
        return 0

    for compiler, result in failures:
        if result.stderr:
            sys.stderr.buffer.write(result.stderr)
        print(
            f"symbol snapshot: {compiler} exited with status "
            f"{result.returncode}",
            file=sys.stderr,
        )
    if not failures:
        print("symbol snapshot: no working compiler is available", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
