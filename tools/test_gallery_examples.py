#!/usr/bin/env python3
"""Focused gallery ownership regressions; run directly with Python."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "gallery", Path(__file__).with_name("check-gallery-examples.py"))
gallery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gallery)


class GalleryExamples(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for module in (gallery, gallery.doc):
            replacement = patch.object(module, "ROOT", self.root)
            replacement.start()
            self.addCleanup(replacement.stop)
        self.write("examples/manifest.txt", "demo|showcase|run\n")

    def write(self, name, content):
        target = self.root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        return target

    def registry(self, entry):
        self.write("examples/gallery.json", json.dumps([entry]))

    def test_slide_spacing_updates_only_the_synchronized_example(self):
        self.registry({"slide": "demo.md", "example": "demo"})
        source = self.write("examples/demo.x", "Map m = %{x: 1};\n")
        expected = "Map m = %{ x: 1 };\n"
        self.write("site/src/content/slides/demo.md", f"```x2c\n{expected}```\n")
        self.assertTrue(gallery.check()[1])
        self.assertEqual(gallery.check(update=True)[1], [])
        self.assertEqual(source.read_text(), expected)
        self.assertEqual(gallery.check()[1], [])

    def test_package_excerpt_never_overwrites_its_owner(self):
        owner = "packages/demo/examples/main.x"
        self.registry({"slide": "demo.md", "source": owner})
        source = self.write(owner, "int main(void) { return 0; }\n")
        original = source.read_bytes()
        slide = self.write("site/src/content/slides/demo.md",
            f"https://github.com/gwf/x2c/blob/main/{owner}\n"
            "<!-- ignore: excerpt requires package setup. -->\n"
            "```x2c,ignore\nrun();\n```\n")
        self.assertEqual(gallery.check(update=True)[1], [])
        self.assertEqual(source.read_bytes(), original)
        slide.write_text(slide.read_text().replace(owner, "wrong.x"))
        self.assertTrue(any("missing source link" in e for e in gallery.check()[1]))
        source.unlink()
        self.assertTrue(any("missing source " in e for e in gallery.check()[1]))

    def test_existing_example_reference_keeps_manifest_coverage(self):
        self.registry({"slide": "demo.md", "source": "examples/demo.x"})
        self.write("examples/demo.x", "int main(void) { return 0; }\n")
        self.write("site/src/content/slides/demo.md",
            "https://github.com/gwf/x2c/blob/main/examples/demo.x\n"
            "```x2c\nint main(void) { return 1; }\n```\n")
        self.assertEqual(gallery.check()[1], [])
        self.write("examples/manifest.txt", "demo|showcase|none\n")
        self.assertTrue(any("manifest coverage" in e for e in gallery.check()[1]))


if __name__ == "__main__":
    unittest.main()
