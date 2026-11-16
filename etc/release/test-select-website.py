import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


def load(name):
    spec = importlib.util.spec_from_file_location(
        name.replace("-", "_"), Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


prepare, selection = load("prepare-website"), load("select-website")
SOURCE = "b" * 40
RELEASE = {"destination": "production", "version": "1.2.3",
           "identity": "candidate-" + "a" * 40 + "-123-1"}
RUN = {"conclusion": "success", "event": "workflow_dispatch",
       "path": ".github/workflows/stage.yml", "head_branch": "dev"}


class WebsiteSelection(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        released, site = self.root / "released", self.root / "site"
        (released / "packages").mkdir(parents=True)
        site.mkdir()
        for name in prepare.PRESERVED:
            if name != "packages":
                (released / name).write_text(
                    json.dumps(RELEASE) if name == "release-candidate.json" else
                    prepare.DOMAINS["production"] if name == "CNAME" else name)
        (released / "packages/index.txt").write_text("index")
        (site / "index.html").write_text("new website")
        self.archive = self.root / "site-production.tar.gz"
        prepare.prepare(site, released, SOURCE, self.archive, "production")

    def select(self, source=SOURCE, run=RUN, live=RELEASE, name="public"):
        selection.select(self.archive, source, run, live, self.root / name)
        return self.root / name

    def test_selected_archive_extracts_with_its_retained_release(self):
        public = self.select()
        self.assertEqual((public / "index.html").read_text(), "new website")
        self.assertEqual((public / "install.sh").read_text(), "install.sh")

    def test_refuses_other_source_run_or_superseded_release(self):
        cases = {
            "source": {"source": "c" * 40},
            "failed": {"run": {**RUN, "conclusion": "failure"}},
            "branch": {"run": {**RUN, "head_branch": "feature"}},
            "workflow": {"run": {**RUN, "path": ".github/workflows/check.yml"}},
            "release": {"live": {**RELEASE, "version": "1.2.4",
                                 "identity": "candidate-" + "d" * 40 + "-9-1"}},
        }
        for name, arguments in cases.items():
            with self.assertRaises(ValueError, msg=name):
                self.select(name=name, **arguments)


if __name__ == "__main__":
    unittest.main()
