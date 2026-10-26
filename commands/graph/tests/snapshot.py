#!/usr/bin/env python3
"""Exercise saved analysis through separate CLI processes and source edits."""

import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


class Project:
    def __init__(self, tool, root):
        self.tool = str(tool)
        self.root = root
        self.query_number = 0

    def command(self, *args, success=True):
        run = subprocess.run(
            [self.tool, *map(str, args)], cwd=self.root,
            capture_output=True, text=True,
        )
        if success:
            assert run.returncode == 0, (run.returncode, args, run.stdout, run.stderr)
            return json.loads(run.stdout)
        assert run.returncode != 0, (run.returncode, args, run.stdout, run.stderr)
        return run

    def query(self, snapshot, **query):
        self.query_number += 1
        path = self.root / f"query-{self.query_number}.json"
        path.write_text(json.dumps(query), encoding="utf-8")
        return self.command("query", snapshot, path)

    def find(self, snapshot, **where):
        return self.query(snapshot, op="find", where=where, limit=10000)


def names(result):
    return {row["name"] for row in result["results"]}


def saved_queries(p, snapshot):
    functions = p.find(snapshot, kind="function")
    assert {"snapshot_entry", "snapshot_middle", "snapshot_leaf"} <= names(functions)
    helpers = p.find(snapshot, kind="function", name="snapshot_helper")
    assert helpers["total"] == 2, helpers
    assert len({row["id"] for row in helpers["results"]}) == 2
    ambiguous = p.query(snapshot, op="inspect", select={"name": "snapshot_helper"})
    assert ambiguous["status"] == "ambiguous", ambiguous
    exact = p.query(snapshot, op="inspect", select={"id": helpers["results"][0]["id"]},
                    view="source")
    assert exact["status"] == "found" and exact["total"] == 1, exact

    forward = p.query(snapshot, op="traverse", select={"name": "snapshot_entry"},
                      relations=["calls"])
    assert {"snapshot_middle", "snapshot_leaf", "snapshot_helper"} <= names(forward)
    reverse = p.query(snapshot, op="traverse", select={"name": "snapshot_leaf"},
                      relations=["calls"], direction="in")
    assert {"snapshot_middle", "snapshot_entry"} <= names(reverse)
    path = p.query(snapshot, op="path", select={"name": "snapshot_entry"},
                   target={"name": "snapshot_leaf"}, relations=["calls"])
    assert path["status"] == "found", path
    edges = path["results"][0]["edges"]
    assert len(edges) == 1 and edges[0].get("file") and edges[0].get("line"), path
    absent = p.query(snapshot, op="path", select={"name": "snapshot_other"},
                     target={"name": "snapshot_leaf"}, relations=["calls"])
    assert absent["status"] == "no-recorded-path", absent

    cycle = p.query(snapshot, op="traverse", select={"name": "snapshot_cycle_a"},
                    relations=["calls"])
    assert names(cycle) == {"snapshot_cycle_a", "snapshot_cycle_b"}, cycle
    assert cycle["total"] == 2, cycle

    aliases = p.find(snapshot, kind="type", name="SnapshotAlias")
    assert aliases["total"] == 1, aliases
    alias = aliases["results"][0]
    assert alias["declared_type"] != alias["resolved_type"], alias
    alias_targets = p.query(snapshot, op="traverse", select={"id": alias["id"]},
                           relations=["aliases"], depth=1)
    assert alias_targets["total"] > 1, alias_targets
    fields = p.find(snapshot, kind="field")
    assert fields["total"] >= 5, fields
    field_ids = [row["id"] for row in fields["results"]]
    for relation in ("field-value", "field-pointer"):
        assert any(p.query(snapshot, op="traverse", select={"id": field},
                           relations=[relation], depth=1)["total"] > 1
                   for field in field_ids), relation
    for relation in ("parameter", "result"):
        assert p.query(snapshot, op="traverse", select={"name": "snapshot_signature"},
                       relations=[relation], depth=1)["total"] > 1, relation
    callbacks = p.query(snapshot, op="traverse", select={"name": "snapshot_callback"},
                        relations=["callback"], depth=1)
    assert callbacks["total"] > 1, callbacks
    writes = p.query(snapshot, op="traverse", select={"name": "snapshot_entry"},
                     relations=["calls", "writes"], where={"kind": "field"})
    assert writes["total"] >= 1, writes
    representation = p.query(snapshot, op="traverse", select={"name": "snapshot_layout"},
                             relations=["representation"], depth=1)
    assert representation["total"] > 1, representation

    boolean = p.query(snapshot, op="find", where={"all": [
        {"kind": "function"}, {"any": [{"name": "snapshot_entry"},
                                       {"name": "snapshot_other"}]},
        {"not": {"name": "snapshot_other"}},
    ]})
    assert names(boolean) == {"snapshot_entry"}, boolean
    reachable = p.query(snapshot, op="find", where={"all": [
        {"kind": "function"},
        {"reachable_from": {"select": {"name": "snapshot_entry"},
                            "relations": ["calls"]}},
    ]})
    assert "snapshot_leaf" in names(reachable) and "snapshot_other" not in names(reachable)

    pattern = "(expr ?type (call ?callee (args *args)))"
    matches = p.query(snapshot, op="match", select={"name": "snapshot_entry"},
                      pattern=pattern, inside="loop", callee="snapshot_leaf")
    assert matches["total"] == 1, matches
    assert matches["results"][0]["captures"], matches
    assert matches["results"][0].get("line"), matches
    typed = p.query(snapshot, op="match", select={"name": "snapshot_entry"},
                    pattern=pattern, inside="loop", callee="snapshot_leaf",
                    argument_type='(* struct "SnapshotValue")')
    assert typed["total"] == 1, typed
    node_filters = {"all": [
        {"inside": "loop"},
        {"any": [{"callee": "snapshot_leaf"}, {"callee": "snapshot_middle"}]},
        {"not": {"argument_type": "(double)"}},
    ]}
    filtered = p.query(snapshot, op="match", select={"name": "snapshot_entry"},
                       pattern=pattern, node_where=node_filters)
    assert filtered["total"] == 1, filtered
    node_filters["all"][-1] = {"not": {"argument_type": '(* struct "SnapshotValue")'}}
    excluded = p.query(snapshot, op="match", select={"name": "snapshot_entry"},
                       pattern=pattern, node_where=node_filters)
    assert excluded["total"] == 0, excluded
    page = p.query(snapshot, op="find", where={"kind": "function"}, limit=1)
    assert len(page["results"]) == 1 and page["truncated"], page
    next_page = p.query(snapshot, op="find", where={"kind": "function"}, limit=1, offset=1)
    assert next_page["results"][0]["id"] != page["results"][0]["id"]
    return functions


def lifecycle(p, sources):
    snapshot = p.root / "before"
    p.command("snapshot", snapshot, *sources)
    assert p.command("status", snapshot)["fresh"]
    functions = saved_queries(p, snapshot)
    assert p.find(snapshot, kind="function") == functions, "reload changed results"
    original = sources[0].read_text()
    source_view = p.query(snapshot, op="inspect", select={"name": "snapshot_leaf"},
                          view="source")
    source = source_view["results"][0]["source"]
    assert "snapshot_leaf(SnapshotValue *value)" in source, source_view
    assert "value.count = snapshot_helper(value.count);" in source, source_view
    assert "return value.count;" in source, source_view
    declaration = p.query(snapshot, op="inspect", select={"name": "snapshot_leaf"},
                          view="declaration")
    signature = declaration["results"][0]["declaration"]
    assert "snapshot_leaf" in signature and "SnapshotValue" in signature, declaration
    ast = p.query(snapshot, op="inspect", select={"name": "snapshot_leaf"},
                  view="typed_ast")
    assert "function" in ast["results"][0]["ast"], ast
    sources[0].write_text(original.replace("value + 1", "value + 2"))
    status = p.command("status", snapshot)
    assert not status["fresh"] and str(sources[0]) in status["changed"], status
    assert p.query(snapshot, op="inspect", select={"name": "snapshot_leaf"},
                   view="source") == source_view, "saved view read live source"
    saved = (snapshot / "snapshot.datum").read_bytes()
    sources[0].write_text("int broken( {\n")
    p.command("snapshot", snapshot, *sources, success=False)
    assert (snapshot / "snapshot.datum").read_bytes() == saved
    assert p.find(snapshot, kind="function") == functions
    sources[0].write_text(original.replace(
        "SnapshotAlias snapshot_signature(SnapshotAlias value) => value;",
        "int snapshot_signature(SnapshotAlias value) => value.count;",
    ).replace("SnapshotValue *pointer;", "SnapshotValue pointer;")
      .replace("int sum = snapshot_middle(value);", "int sum = snapshot_leaf(value);"))
    after = p.root / "after"
    p.command("snapshot", after, *sources)
    difference = p.command("diff", snapshot, after)
    assert difference["changed"], difference
    assert difference["added_relations"] and difference["removed_relations"], difference
    sources[1].unlink()
    missing = p.command("status", snapshot)
    assert str(sources[1]) in missing["missing"], missing
    assert p.find(snapshot, kind="function") == functions
    damaged = p.root / "incompatible"
    shutil.copytree(snapshot, damaged)
    data_path = damaged / "snapshot.datum"
    text = data_path.read_text()
    replaced, count = re.subn(r'("compiler"\s+)"[^"]*"', r'\1"incompatible"', text, count=1)
    assert count == 1, "compiler identity missing from snapshot"
    data_path.write_text(replaced)
    failure = p.command("status", damaged, success=False)
    assert "incompatible" in failure.stderr


def project_membership(p):
    directory = p.root / "project"
    directory.mkdir()
    (directory / "core.x").write_text("int snapshot_core(void) => 1;\n")
    (directory / "app.x").write_text("int snapshot_core(void);\nint main(void) => snapshot_core();\n")
    manifest = directory / "x2c.toml"
    manifest.write_text('''[project]
default-target = "app"
[target.core]
kind = "static-library"
sources = ["core.x"]
[target.app]
sources = ["app*.x"]
dependencies = ["core"]
''')
    snapshot = p.root / "manifest"
    p.command("snapshot", snapshot, "--manifest-path", manifest)
    assert p.command("status", snapshot)["fresh"]
    path = p.query(snapshot, op="path", select={"name": "main"},
                   target={"name": "snapshot_core", "kind": "function", "domain": "core"})
    assert path["status"] == "found", path
    assert {row["domain"] for row in p.find(snapshot, kind="function")["results"]} >= {"app", "core"}
    (directory / "app-extra.x").write_text("int snapshot_added(void) => 2;\n")
    status = p.command("status", snapshot)
    assert not status["fresh"] and status["added_inputs"], status
    assert not (directory / ".x2c-build" / "app").exists(), "snapshot built application"


def protocol_relationships(p, fixture):
    source = p.root / fixture.name
    shutil.copyfile(fixture, source)
    snapshot = p.root / "protocols"
    p.command("snapshot", snapshot, source)
    types = p.find(snapshot, kind="type")["results"]
    for relation in ("conforms", "delegates"):
        assert any(p.query(snapshot, op="traverse", select={"id": row["id"]},
                           relations=[relation], depth=1)["total"] > 1
                   for row in types), relation


def main():
    directory = Path(__file__).resolve().parent
    tool = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else (
        directory.parents[2] / "builds/0/libexec/x2c-graph"
    )
    with tempfile.TemporaryDirectory(prefix="x2c-snapshot-test-") as temporary:
        root = Path(temporary).resolve()
        sources = []
        for name in ("snapshot-a.x", "snapshot-b.x"):
            target = root / name
            shutil.copyfile(directory / "fixtures" / name, target)
            sources.append(target)
        project = Project(tool, root)
        lifecycle(project, sources)
        project_membership(project)
        protocol_relationships(project, directory / "fixtures/snapshot-protocol.x")
    print("snapshot acceptance passed")


if __name__ == "__main__":
    main()
