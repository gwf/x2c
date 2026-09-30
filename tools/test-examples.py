#!/usr/bin/env python3
"""Check the examples runner's manifest and argv behavior without compiling."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


CHECKER = Path(__file__).resolve().parent.parent / "examples/check.sh"
BASH = shutil.which("bash")


class ExamplesCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="x2c examples check ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.examples = self.root / "examples"
        self.examples.mkdir()
        shutil.copy2(CHECKER, self.examples / "check.sh")
        for name in ("love", "power", "magic", "programs", "scripts", "tours"):
            (self.examples / name).mkdir()
        greet = self.examples / "packages/greet"
        greet.mkdir(parents=True)
        (greet / "Makefile").write_text(".PHONY: build\nbuild:\n\t@:\n")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.bin / "bash").symlink_to(BASH)
        self.executable("x2c", "#!/bin/sh\nexit 0\n")
        self.executable("cc", r"""#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
args = sys.argv[1:]
Path(os.environ["EXAMPLES_CC_LOG"]).write_text(json.dumps(args))
program = Path(args[args.index("-o") + 1])
program.write_text('#!/bin/sh\nfor arg in "$@"; do printf "%s\\n" "$arg"; done\n')
program.chmod(0o755)
""")

    def executable(self, name, source):
        path = self.bin / name
        path.write_text(source)
        path.chmod(0o755)

    def source(self, name):
        path = self.examples / (name + ".x")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("int main(void) { return 0; }\n")

    def run_check(self, manifest, linker_flags=""):
        (self.examples / "manifest.txt").write_text(manifest)
        env = os.environ.copy()
        env.update({
            "PATH": str(self.bin) + os.pathsep + env["PATH"],
            "X2C": str(self.bin / "x2c"),
            "CC": str(self.bin / "cc"),
            "EXAMPLES_CC_LOG": str(self.root / "cc.json"),
            "BUILD_LDFLAGS": linker_flags,
            "JOBS": "1",
        })
        return subprocess.run(
            [BASH, str(self.examples / "check.sh"), "check"],
            env=env, text=True, capture_output=True, timeout=30,
        )

    def test_empty_arguments_and_linker_flags(self):
        self.source("plain")
        result = self.run_check("plain|showcase|run||-|empty argv\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertIn("1 passed (1 run, 0 build-only)", result.stdout)
        args = json.loads((self.root / "cc.json").read_text())
        self.assertNotIn("", args)
        self.assertIn(str(self.root / "include/x2c"), args)

    def test_arguments_and_linker_flags_remain_separate(self):
        self.source("args")
        expected = self.examples / "expected"
        expected.mkdir()
        (expected / "args.stdout").write_text("one\n*.txt\n")
        data = self.examples / "data/args"
        data.mkdir(parents=True)
        (data / "match.txt").write_text("must not expand the argv glob\n")
        result = self.run_check(
            "args|showcase|run|one *.txt|expected/args.stdout|argv\n",
            "-Wl,probe-one -Wl,probe-two",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        args = json.loads((self.root / "cc.json").read_text())
        start = args.index("-Wl,probe-one")
        self.assertEqual(args[start:start + 2],
                         ["-Wl,probe-one", "-Wl,probe-two"])

    def test_duplicate_names_are_literal(self):
        names = ("love/maps", "a*[b]?", "a*[c]?")
        for name in names:
            self.source(name)
        manifest = "".join(name + "|legacy|none||-|literal name\n"
                           for name in names + ("a*[b]?",))
        result = self.run_check(manifest)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr.count("appears more than once"), 1)
        self.assertIn("a*[b]? appears more than once", result.stderr)
        self.assertNotIn("not classified", result.stderr)

    def test_unclassified_source_with_no_work(self):
        self.source("missing")
        result = self.run_check("# no executable work\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing.x is not classified", result.stderr)
        self.assertNotIn("unbound variable", result.stderr)

    def test_malformed_manifest_row(self):
        result = self.run_check("malformed|row\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("malformed manifest row: malformed|row", result.stderr)
        self.assertIn("0 classified, 0 checked", result.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bash", default=BASH,
                        help="Bash executable used by the runner and workers")
    BASH = str(Path(parser.parse_args().bash).resolve())
    unittest.main(argv=[__file__])
