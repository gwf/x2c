#!/usr/bin/env python3
"""Prepare checksum-pinned integration dependencies in one shared cache."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.parse
import urllib.request
import zipfile


SCHEMA_VERSION = 1
CACHE_FORMAT_VERSION = 2


class DependencyError(RuntimeError):
  pass


def _run_output(argv: list[str], cwd: Path | None = None) -> str:
  try:
    result = subprocess.run(
      argv, cwd=cwd, check=True, text=True, stdout=subprocess.PIPE,
      stderr=subprocess.STDOUT
    )
  except (OSError, subprocess.CalledProcessError) as error:
    output = getattr(error, "stdout", "") or ""
    raise DependencyError(
      f"command failed: {shlex.join(argv)}\n{output.rstrip()}"
    ) from error
  return result.stdout.strip()


def _cache_root(manifest_path: Path) -> Path:
  override = os.environ.get("X2C_DEPS_DIR")
  if override:
    return Path(override).expanduser().resolve()
  common = _run_output(
    ["git", "-C", str(manifest_path.parent), "rev-parse", "--path-format=absolute",
     "--git-common-dir"]
  )
  return Path(common).resolve() / "x2c-integrations"


def _compiler() -> tuple[list[str], str]:
  command = shlex.split(os.environ.get("CC", "cc"))
  if not command:
    raise DependencyError("CC names no compiler")
  executable = shutil.which(command[0])
  if not executable:
    raise DependencyError(f"C compiler not found: {command[0]}")
  command[0] = executable
  identity = _run_output(command + ["--version"]).splitlines()[0]
  return command, identity


def _archiver() -> list[str]:
  command = shlex.split(os.environ.get("AR", "ar"))
  if not command:
    raise DependencyError("AR names no archiver")
  executable = shutil.which(command[0])
  if not executable:
    raise DependencyError(f"archiver not found: {command[0]}")
  command[0] = executable
  return command


def _load_manifest(path: Path) -> tuple[dict, bytes]:
  try:
    raw = path.read_bytes()
    manifest = json.loads(raw)
  except (OSError, json.JSONDecodeError) as error:
    raise DependencyError(f"cannot read manifest {path}: {error}") from error
  if manifest.get("schema") != SCHEMA_VERSION:
    raise DependencyError(
      f"{path}: expected schema {SCHEMA_VERSION}, "
      f"found {manifest.get('schema')!r}"
    )
  if not manifest.get("name") or not manifest.get("sources"):
    raise DependencyError(f"{path}: name and sources are required")
  package_name = PurePosixPath(manifest["name"])
  if len(package_name.parts) != 1 or package_name.name in (".", ".."):
    raise DependencyError(f"{path}: name must be one path component")
  names = [source.get("name") for source in manifest["sources"]]
  if any(not name for name in names) or len(names) != len(set(names)):
    raise DependencyError(f"{path}: source names must be present and unique")
  for source in manifest["sources"]:
    source_name = PurePosixPath(source["name"])
    if len(source_name.parts) != 1 or source_name.name in (".", ".."):
      raise DependencyError(
        f"{path}: source name must be one path component"
      )
    digest = source.get("sha256", "")
    if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
      raise DependencyError(
        f"{path}: source {source['name']} has an invalid sha256"
      )
    if not source.get("url") or not source.get("root"):
      raise DependencyError(
        f"{path}: source {source['name']} needs url and root"
      )
    root = PurePosixPath(source["root"])
    if not root.parts or root.is_absolute() or ".." in root.parts:
      raise DependencyError(
        f"{path}: source {source['name']} has an unsafe root"
      )
  for item in manifest.get("inputs", []):
    local = path.parent / item["path"]
    if not local.is_file() or _sha256(local) != item["sha256"]:
      raise DependencyError(f"local input has wrong hash or is missing: {local}")
  return manifest, raw


def _context(path: Path) -> dict:
  manifest, raw = _load_manifest(path)
  compiler, compiler_identity = _compiler()
  archiver = _archiver()
  identity = {
    "platform": sys.platform,
    "machine": platform.machine(),
    "compiler": compiler_identity,
    "compiler_command": compiler,
  }
  key_hash = hashlib.sha256()
  key_hash.update(raw)
  key_hash.update(b"\0")
  key_hash.update(json.dumps(identity, sort_keys=True).encode())
  key_hash.update(b"\0")
  key_hash.update(str(CACHE_FORMAT_VERSION).encode())
  key = key_hash.hexdigest()
  cache = _cache_root(path)
  entry = cache / "entries" / manifest["name"] / key
  object_path = cache / "objects" / manifest["name"] / key
  source_paths = {
    source["name"]: entry / "sources" / source["name"]
    for source in manifest["sources"]
  }
  return {
    "manifest": manifest,
    "manifest_path": path,
    "manifest_sha256": hashlib.sha256(raw).hexdigest(),
    "cache": cache,
    "entry": entry,
    "object": object_path,
    "prefix": entry / "prefix",
    "sources": source_paths,
    "key": key,
    "identity": identity,
    "compiler": compiler,
    "archiver": archiver,
  }


def _download_path(context: dict, source: dict) -> Path:
  basename = Path(urllib.parse.urlparse(source["url"]).path).name
  if not basename:
    basename = f"{source['name']}.tar"
  return context["cache"] / "downloads" / (
    f"{source['sha256']}-{basename}"
  )


def _sha256(path: Path) -> str:
  digest = hashlib.sha256()
  with path.open("rb") as stream:
    while block := stream.read(1024 * 1024):
      digest.update(block)
  return digest.hexdigest()


def _download(context: dict, source: dict) -> Path:
  destination = _download_path(context, source)
  destination.parent.mkdir(parents=True, exist_ok=True)
  if destination.is_file():
    if _sha256(destination) == source["sha256"]:
      return destination
    raise DependencyError(f"cached archive has wrong hash: {destination}")

  temporary = destination.with_name(
    f".{destination.name}.tmp-{os.getpid()}-{time.time_ns()}"
  )
  print(f"download {source['url']}", flush=True)
  try:
    request = urllib.request.Request(
      source["url"], headers={"User-Agent": "x2c-integration-deps/1"}
    )
    with urllib.request.urlopen(request) as response:
      with temporary.open("wb") as output:
        shutil.copyfileobj(response, output)
    actual = _sha256(temporary)
    if actual != source["sha256"]:
      raise DependencyError(
        f"{source['name']}: expected {source['sha256']}, downloaded {actual}"
      )
    try:
      os.link(temporary, destination)
    except FileExistsError:
      if _sha256(destination) != source["sha256"]:
        raise DependencyError(
          f"concurrent download produced wrong hash: {destination}"
        )
    return destination
  finally:
    temporary.unlink(missing_ok=True)


def _member_destination(root: Path, name: str) -> Path:
  pure = PurePosixPath(name)
  if pure.is_absolute() or ".." in pure.parts:
    raise DependencyError(f"archive contains unsafe path: {name}")
  destination = (root / Path(*pure.parts)).resolve()
  if os.path.commonpath([root.resolve(), destination]) != str(root.resolve()):
    raise DependencyError(f"archive path escapes extraction root: {name}")
  return destination


def _link_destination(root: Path, member: tarfile.TarInfo) -> Path:
  target = PurePosixPath(member.linkname)
  if target.is_absolute():
    raise DependencyError(f"archive contains unsafe link: {member.name}")
  member_path = _member_destination(root, member.name)
  base = member_path.parent if member.issym() else root
  destination = (base / Path(*target.parts)).resolve()
  if os.path.commonpath([root.resolve(), destination]) != str(root.resolve()):
    raise DependencyError(f"archive contains unsafe link: {member.name}")
  return destination


def _extract_zip(archive: Path, raw: Path) -> None:
  with zipfile.ZipFile(archive) as bundle:
    for member in bundle.infolist():
      if member.is_dir():
        continue
      target = _member_destination(raw, member.filename)
      target.parent.mkdir(parents=True, exist_ok=True)
      with bundle.open(member) as data, target.open("wb") as output:
        shutil.copyfileobj(data, output)
      mode = (member.external_attr >> 16) & 0o777
      if mode:
        target.chmod(mode)


def _extract(archive: Path, source: dict, destination: Path) -> None:
  raw = destination.parent / f".{source['name']}-extract"
  raw.mkdir(parents=True)
  try:
    if zipfile.is_zipfile(archive):
      _extract_zip(archive, raw)
    else:
      with tarfile.open(archive, "r:*") as bundle:
        for member in bundle.getmembers():
          _member_destination(raw, member.name)
          if member.issym() or member.islnk():
            _link_destination(raw, member)
        bundle.extractall(raw, filter="data")
    root = raw / source["root"]
    if not root.is_dir():
      raise DependencyError(
        f"{source['name']}: archive root {source['root']} was not found"
      )
    root.rename(destination)
  finally:
    shutil.rmtree(raw, ignore_errors=True)


def _format(value: str, variables: dict[str, str]) -> str:
  try:
    return value.format_map(variables)
  except KeyError as error:
    raise DependencyError(f"unknown manifest variable: {error.args[0]}")


def _variables(context: dict, entry: Path) -> dict[str, str]:
  variables = {
    "package": str(context["manifest_path"].resolve().parent),
    "entry": str(entry),
    "prefix": str(entry / "prefix"),
    "work": str(entry / "work"),
    "jobs": str(max(1, os.cpu_count() or 1)),
    "cc": context["compiler"][0],
    "ar": context["archiver"][0],
  }
  for name in context["sources"]:
    variables[f"source_{name}"] = str(entry / "sources" / name)
  return variables


def _run_steps(context: dict, entry: Path) -> None:
  variables = _variables(context, entry)
  for index, step in enumerate(context["manifest"].get("steps", []), 1):
    argv = [_format(argument, variables) for argument in step.get("argv", [])]
    if not argv:
      raise DependencyError(f"build step {index} has no argv")
    cwd = Path(_format(step.get("cwd", "{work}"), variables))
    environment = os.environ.copy()
    for name, value in step.get("env", {}).items():
      environment[name] = _format(value, variables)
    print(f"[{context['manifest']['name']} {index}] {shlex.join(argv)}")
    try:
      subprocess.run(argv, cwd=cwd, env=environment, check=True)
    except (OSError, subprocess.CalledProcessError) as error:
      raise DependencyError(
        f"build step {index} failed: {shlex.join(argv)}"
      ) from error


def _copy_files(context: dict, entry: Path) -> None:
  variables = _variables(context, entry)
  for item in context["manifest"].get("copies", []):
    source = Path(_format(item["from"], variables))
    destination = Path(_format(item["to"], variables))
    if not source.is_file():
      raise DependencyError(f"copy source does not exist: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def _verify_receipts(context: dict, entry: Path) -> None:
  variables = _variables(context, entry)
  for receipt in context["manifest"].get("receipts", []):
    path = Path(_format(receipt, variables))
    if not path.exists():
      raise DependencyError(f"missing dependency receipt: {path}")


def _receipt_path(entry: Path) -> Path:
  return entry / "receipt.json"


def _entry_complete(context: dict) -> bool:
  receipt = _receipt_path(context["entry"])
  if not receipt.is_file():
    return False
  try:
    data = json.loads(receipt.read_text())
    if data.get("key") != context["key"]:
      return False
    if data.get("cache_format") != CACHE_FORMAT_VERSION:
      return False
    _verify_receipts(context, context["entry"])
  except (OSError, json.JSONDecodeError, DependencyError):
    return False
  return True


def _missing_command(command: str, missing: dict[str, str],
                     package: str) -> bool:
  argv = shlex.split(command)
  if not argv or not shutil.which(argv[0]):
    missing[command or "(empty command)"] = package
    return True
  return False


def _native_missing(manifest: dict) -> dict[str, str]:
  missing: dict[str, str] = {}
  packages = {"make": "make", "patch": "patch", "sh": "bash"}
  for step in manifest.get("steps", []):
    command = step["argv"][0]
    if not command.startswith(("./", "{")):
      _missing_command(shlex.quote(command), missing,
                       packages.get(command, command))
  name = manifest["name"]
  if name == "libuv":
    for variable, default, package in (
      ("ACLOCAL", "aclocal", "automake"),
      ("AUTOCONF", "autoconf", "autoconf"),
      ("AUTOMAKE", "automake", "automake"),
      ("LIBTOOLIZE", "glibtoolize" if sys.platform == "darwin"
       else "libtoolize", "libtool"),
      ("M4", "m4", "m4"),
    ):
      _missing_command(shlex.quote(os.environ.get(variable) or default),
                       missing, package)
  if name == "blis":
    _missing_command("bash", missing, "bash")
    _missing_command("perl", missing, "perl")
    _missing_command(os.environ.get("PYTHON") or "python3", missing,
                     "python3")
  if any(source["name"] == "openssl" for source in manifest["sources"]):
    if not _missing_command("perl", missing, "perl"):
      for module in ("FindBin", "IPC::Cmd"):
        result = subprocess.run(
          ["perl", "-M" + module, "-e", "1"],
          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        if result.returncode:
          missing["Perl module " + module] = "perl-" + module.replace("::", "-")
  return missing


def _missing_message(missing: dict[str, str]) -> str:
  return ("missing build prerequisites: " + ", ".join(missing) +
          "\nFedora: sudo dnf install " +
          " ".join(sorted(set(missing.values()))) +
          "\nFor overridden commands, install or correct the selected tool.")


def _preflight(names: list[str]) -> int:
  root = Path(__file__).resolve().parent.parent
  available = sorted(path.parent.name for path in root.glob("*/dependency.json"))
  if not names:
    names = available
  missing: dict[str, str] = {}
  archiver = os.environ.get("X2C_AR")
  if archiver and not shutil.which(archiver):
    missing[archiver] = "binutils"
  for name in names:
    if name not in available:
      raise DependencyError(f"unknown package: {name}")
    if name != "raylib":
      _missing_command("shasum", missing, "perl-Digest-SHA")
    if name == "blis":
      for command, package in (("jq", "jq"), ("nm", "binutils"),
                               ("ar", "binutils")):
        _missing_command(command, missing, package)
    variable = "CURL_PREFIX" if name == "libcurl" else name.upper() + "_PREFIX"
    if os.environ.get(variable):
      continue
    path = root / name / "dependency.json"
    linux = path.with_name("dependency-linux.json")
    if sys.platform == "linux" and linux.is_file():
      path = linux
    manifest, _ = _load_manifest(path)
    cannot_inspect = False
    for command, package in (("git", "git"),
                             (os.environ.get("CC", "cc"), "gcc"),
                             (os.environ.get("AR", "ar"), "binutils")):
      cannot_inspect |= _missing_command(command, missing, package)
    if not cannot_inspect and _entry_complete(_context(path)):
      continue
    missing.update(_native_missing(manifest))
  print("Terminal validation uses Expect; package builds do not require it.")
  if missing:
    print(_missing_message(missing), file=sys.stderr)
    return 1
  print("Package build prerequisites are available.")
  return 0


def _prepare(context: dict) -> str:
  cache = context["cache"]
  cache.mkdir(parents=True, exist_ok=True)
  lock_path = cache / "locks" / (
    f"{context['manifest']['name']}-{context['key']}.lock"
  )
  lock_path.parent.mkdir(parents=True, exist_ok=True)
  with lock_path.open("a+") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    if _entry_complete(context):
      return "reused"
    missing = _native_missing(context["manifest"])
    if missing:
      raise DependencyError(_missing_message(missing))

    entry_parent = context["entry"].parent
    entry_parent.mkdir(parents=True, exist_ok=True)
    if context["entry"].exists():
      failures = cache / "failures"
      failures.mkdir(parents=True, exist_ok=True)
      stale = failures / (
        f"{context['manifest']['name']}-{context['key'][:12]}-"
        f"entry-{time.time_ns()}"
      )
      context["entry"].rename(stale)
    temporary_entry = Path(tempfile.mkdtemp(
      prefix=f".{context['key']}.entry-", dir=entry_parent
    ))
    object_path = context["object"]
    object_path.parent.mkdir(parents=True, exist_ok=True)
    if object_path.exists():
      failures = cache / "failures"
      failures.mkdir(parents=True, exist_ok=True)
      stale = failures / (
        f"{context['manifest']['name']}-{context['key'][:12]}-"
        f"stale-{time.time_ns()}"
      )
      object_path.rename(stale)
    (object_path / "prefix" / "include").mkdir(parents=True)
    (object_path / "prefix" / "lib").mkdir(parents=True)
    (object_path / "prefix" / "bin").mkdir(parents=True)
    (object_path / "sources").mkdir()
    (object_path / "work").mkdir()
    try:
      for source in context["manifest"]["sources"]:
        archive = _download(context, source)
        _extract(
          archive, source, object_path / "sources" / source["name"]
        )
      _run_steps(context, object_path)
      _copy_files(context, object_path)
      _verify_receipts(context, object_path)
      for name in ("prefix", "sources", "work"):
        (temporary_entry / name).symlink_to(
          object_path / name, target_is_directory=True
        )
      receipt = {
        "schema": SCHEMA_VERSION,
        "cache_format": CACHE_FORMAT_VERSION,
        "name": context["manifest"]["name"],
        "version": context["manifest"].get("version"),
        "profile": context["manifest"].get("profile"),
        "key": context["key"],
        "manifest_sha256": context["manifest_sha256"],
        "identity": context["identity"],
      }
      _receipt_path(temporary_entry).write_text(
        json.dumps(receipt, indent=2, sort_keys=True) + "\n"
      )
      if context["entry"].exists():
        raise DependencyError(
          f"incomplete cache entry already exists: {context['entry']}"
        )
      temporary_entry.rename(context["entry"])
      return "prepared"
    except Exception:
      failures = cache / "failures"
      failures.mkdir(parents=True, exist_ok=True)
      failure = failures / (
        f"{context['manifest']['name']}-{context['key'][:12]}-"
        f"{time.time_ns()}"
      )
      if object_path.exists():
        object_path.rename(failure)
      shutil.rmtree(temporary_entry, ignore_errors=True)
      print(f"failed build retained at {failure}", file=sys.stderr)
      raise


def _path(context: dict, kind: str, source: str | None) -> Path:
  if kind == "cache":
    return context["cache"]
  if kind == "entry":
    return context["entry"]
  if kind == "prefix":
    return context["prefix"]
  if kind == "source":
    if not source:
      if len(context["sources"]) != 1:
        raise DependencyError("source name is required for this manifest")
      source = next(iter(context["sources"]))
    if source not in context["sources"]:
      raise DependencyError(f"unknown source: {source}")
    return context["sources"][source]
  if kind == "archive":
    sources = {
      item["name"]: item for item in context["manifest"]["sources"]
    }
    if not source:
      if len(sources) != 1:
        raise DependencyError("source name is required for this manifest")
      source = next(iter(sources))
    if source not in sources:
      raise DependencyError(f"unknown source: {source}")
    return _download_path(context, sources[source])
  raise DependencyError(f"unknown path kind: {kind}")


def _parser() -> argparse.ArgumentParser:
  parser = argparse.ArgumentParser()
  subparsers = parser.add_subparsers(dest="command", required=True)

  for name in ("prepare", "verify", "key"):
    command = subparsers.add_parser(name)
    command.add_argument("manifest", type=Path)

  preflight = subparsers.add_parser("preflight")
  preflight.add_argument("packages", nargs="*")

  path = subparsers.add_parser("path")
  path.add_argument("manifest", type=Path)
  path.add_argument(
    "kind", choices=("cache", "entry", "prefix", "source", "archive")
  )
  path.add_argument("source", nargs="?")
  return parser


def main() -> int:
  arguments = _parser().parse_args()
  if arguments.command == "preflight":
    return _preflight(arguments.packages)
  context = _context(arguments.manifest.resolve())
  if arguments.command == "path":
    print(_path(context, arguments.kind, arguments.source))
    return 0
  if arguments.command == "key":
    print(context["key"])
    return 0
  if arguments.command == "verify":
    if not _entry_complete(context):
      raise DependencyError(
        f"dependency is not prepared: {context['manifest']['name']}"
      )
    print(f"verified {context['manifest']['name']} {context['key']}")
    return 0
  result = _prepare(context)
  print(
    f"{result} {context['manifest']['name']} {context['key']} "
    f"{context['prefix']}"
  )
  return 0


if __name__ == "__main__":
  try:
    raise SystemExit(main())
  except DependencyError as error:
    print(f"dependency error: {error}", file=sys.stderr)
    raise SystemExit(2)
