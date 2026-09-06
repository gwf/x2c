#!/usr/bin/env python3
"""Focused tests for the shared integration dependency cache."""

from __future__ import annotations

import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

import deps


class DependencyCacheTests(unittest.TestCase):
  def setUp(self) -> None:
    self.temporary = tempfile.TemporaryDirectory(
      prefix="x2c-deps-test."
    )
    self.root = Path(self.temporary.name)
    subprocess.run(
      ["git", "init", "--quiet", str(self.root)], check=True
    )
    self.cache = self.root / "cache"
    self.previous_cache = os.environ.get("X2C_DEPS_DIR")
    os.environ["X2C_DEPS_DIR"] = str(self.cache)

  def tearDown(self) -> None:
    if self.previous_cache is None:
      os.environ.pop("X2C_DEPS_DIR", None)
    else:
      os.environ["X2C_DEPS_DIR"] = self.previous_cache
    self.temporary.cleanup()

  def _archive(self, unsafe: bool = False) -> Path:
    archive = self.root / ("unsafe.tar.gz" if unsafe else "source.tar.gz")
    with tarfile.open(archive, "w:gz") as bundle:
      name = "../escape" if unsafe else "sample-1.0/include/sample.h"
      content = b"sample\n"
      member = tarfile.TarInfo(name)
      member.size = len(content)
      bundle.addfile(member, io.BytesIO(content))
    return archive

  def _link_archive(self, target: str) -> Path:
    archive = self.root / "link.tar.gz"
    with tarfile.open(archive, "w:gz") as bundle:
      directory = tarfile.TarInfo("sample-1.0/nested")
      directory.type = tarfile.DIRTYPE
      bundle.addfile(directory)
      link = tarfile.TarInfo("sample-1.0/nested/header.h")
      link.type = tarfile.SYMTYPE
      link.linkname = target
      bundle.addfile(link)
    return archive

  def _manifest(self, archive: Path, profile: str = "test") -> Path:
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    manifest = {
      "schema": 1,
      "name": "sample",
      "version": "1.0",
      "profile": profile,
      "sources": [{
        "name": "sample",
        "url": archive.as_uri(),
        "sha256": digest,
        "root": "sample-1.0",
      }],
      "copies": [{
        "from": "{source_sample}/include/sample.h",
        "to": "{prefix}/include/sample.h",
      }],
      "steps": [{
        "argv": [
          sys.executable, "-c",
          "from pathlib import Path; import sys; "
          "Path(sys.argv[1], 'embedded-prefix').write_text(sys.argv[1])",
          "{prefix}",
        ],
      }],
      "receipts": [
        "{prefix}/include/sample.h",
        "{prefix}/embedded-prefix",
      ],
    }
    path = self.root / f"dependency-{profile}.json"
    path.write_text(json.dumps(manifest, indent=2) + "\n")
    return path

  def test_prepare_then_reuse(self) -> None:
    context = deps._context(self._manifest(self._archive()))
    self.assertEqual(deps._prepare(context), "prepared")
    self.assertEqual(deps._prepare(context), "reused")
    self.assertTrue((context["prefix"] / "include/sample.h").is_file())
    self.assertTrue(deps._entry_complete(context))
    embedded = (context["prefix"] / "embedded-prefix").read_text()
    self.assertEqual(embedded, str(context["prefix"].resolve()))

  def test_manifest_change_changes_key(self) -> None:
    archive = self._archive()
    first = deps._context(self._manifest(archive, "one"))
    second = deps._context(self._manifest(archive, "two"))
    self.assertNotEqual(first["key"], second["key"])

  def test_local_input_change_cannot_reuse_cached_build(self) -> None:
    path = self._manifest(self._archive())
    local = self.root / "patch.txt"
    local.write_text("first\n")
    manifest = json.loads(path.read_text())
    manifest["inputs"] = [{
      "path": local.name,
      "sha256": hashlib.sha256(local.read_bytes()).hexdigest(),
    }]
    manifest["steps"][0]["argv"] = [
      sys.executable, "-c",
      "from pathlib import Path; import sys; "
      "Path(sys.argv[2], 'embedded-prefix').write_bytes("
      "Path(sys.argv[1], 'patch.txt').read_bytes())",
      "{package}", "{prefix}",
    ]
    path.write_text(json.dumps(manifest))
    first = deps._context(path)
    self.assertEqual(deps._prepare(first), "prepared")
    self.assertEqual((first["prefix"] / "embedded-prefix").read_text(), "first\n")
    local.write_text("second\n")
    with self.assertRaises(deps.DependencyError):
      deps._context(path)
    manifest["inputs"][0]["sha256"] = hashlib.sha256(local.read_bytes()).hexdigest()
    path.write_text(json.dumps(manifest))
    second = deps._context(path)
    self.assertNotEqual(first["key"], second["key"])
    self.assertEqual(deps._prepare(second), "prepared")
    self.assertEqual((second["prefix"] / "embedded-prefix").read_text(), "second\n")

  def test_concurrent_prepare_publishes_once(self) -> None:
    manifest = self._manifest(self._archive())
    command = [sys.executable, str(Path(deps.__file__)), "prepare",
               str(manifest)]
    processes = [
      subprocess.Popen(
        command, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT
      )
      for _ in range(2)
    ]
    outputs = [process.communicate()[0] for process in processes]
    self.assertTrue(all(process.returncode == 0 for process in processes))
    self.assertEqual(sum("prepared sample" in output for output in outputs), 1)
    self.assertEqual(sum("reused sample" in output for output in outputs), 1)

  def test_unsafe_archive_path_is_rejected(self) -> None:
    archive = self._archive(unsafe=True)
    destination = self.root / "extracted" / "sample"
    destination.parent.mkdir()
    source = {"name": "sample", "root": "sample-1.0"}
    with self.assertRaises(deps.DependencyError):
      deps._extract(archive, source, destination)
    self.assertFalse((self.root / "escape").exists())

  def test_link_may_move_within_archive_but_not_escape(self) -> None:
    source = {"name": "sample", "root": "sample-1.0"}
    inside = self.root / "inside" / "sample"
    inside.parent.mkdir()
    deps._extract(self._link_archive("../target.h"), source, inside)
    self.assertTrue((inside / "nested/header.h").is_symlink())

    outside = self.root / "outside" / "sample"
    outside.parent.mkdir()
    with self.assertRaises(deps.DependencyError):
      deps._extract(self._link_archive("../../../escape"), source, outside)


if __name__ == "__main__":
  unittest.main()
