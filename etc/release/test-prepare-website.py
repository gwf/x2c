import importlib.util
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "prepare", Path(__file__).with_name("prepare-website.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class WebsitePreparation(unittest.TestCase):
    def prepared(self, root, destination, html):
        staged, site = root / "staged", root / "site"
        staged.mkdir()
        site.mkdir()
        identity = "candidate-" + "a" * 40 + "-123-1"
        release = json.dumps({"destination": destination, "identity": identity})
        for name in module.PRESERVED:
            if name == "packages":
                for base in (staged, site):
                    (base / name).mkdir()
                (staged / name / "index.txt").write_bytes(b"retained package index")
                (site / name / "wrong.txt").write_bytes(b"must disappear")
            else:
                data = (release if name == "release-candidate.json" else
                        module.DOMAINS[destination] if name == "CNAME" else name)
                (staged / name).write_text(data)
                (site / name).write_text("wrong")
        (site / "index.html").write_text(html.format(identity=identity))
        return staged, site, identity

    def test_release_files_survive_conflicting_website_output(self):
        source = "b" * 40
        pages = {
            "staging": '<meta name="x2c-release-channel" content="staging">'
                       f'<meta name="x2c-site-source" content="{source}">'
                       '<meta name="x2c-candidate" content="{identity}">new website',
            "production": "new website"}
        for destination, html in pages.items():
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                staged, site, identity = self.prepared(root, destination, html)
                archive = root / "website.tar.gz"
                module.prepare(site, staged, source, archive, destination)
                for original in staged.rglob("*"):
                    if original.is_file():
                        self.assertEqual(original.read_bytes(),
                            (site / original.relative_to(staged)).read_bytes())
                self.assertFalse((site / "packages/wrong.txt").exists())
                with tarfile.open(archive) as tar:
                    self.assertEqual(tar.extractfile("install.sh").read(), b"install.sh")
                    self.assertIn(b"new website", tar.extractfile("index.html").read())
                receipt = json.loads((site / "website-deployment.json").read_text())
                self.assertEqual(receipt["destination"], destination)
                self.assertEqual(receipt["retained_candidate"], identity)
                self.assertEqual(receipt["source_sha"], source)

    def test_a_build_for_the_other_destination_is_refused(self):
        source = "b" * 40
        staging_html = ('<meta name="x2c-release-channel" content="staging">'
                        f'<meta name="x2c-site-source" content="{source}">'
                        '<meta name="x2c-candidate" content="{identity}">')
        for destination, html in (("production", staging_html), ("staging", "plain")):
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                staged, site, _ = self.prepared(root, destination, html)
                with self.assertRaises(ValueError):
                    module.prepare(site, staged, source, root / "w.tar.gz", destination)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            staged, site, _ = self.prepared(root, "staging", staging_html)
            with self.assertRaises(ValueError):
                module.prepare(site, staged, source, root / "w.tar.gz", "production")


if __name__ == "__main__":
    unittest.main()
