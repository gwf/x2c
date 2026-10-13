#!/usr/bin/env python3
"""Focused tests for the agent failure index."""

import importlib.util
from pathlib import Path
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    "agent_failure", Path(__file__).with_name("agent-failure.py"))
failure = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(failure)
ROW = ("| 2026-10-13 | false-claim | said it passed | `abcd1234` | "
       "`/tmp/incident` | open |")


def cells(line):
    return line.strip().strip("|").split("|")


class AgentFailureIndexTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.index = Path(self.temporary.name) / "agent-failures.md"

    def test_first_capture_writes_a_plan_index_matching_its_rows(self):
        self.assertTrue(failure.append_index(str(self.index), ROW))
        lines = self.index.read_text().splitlines()
        self.assertTrue(any(line.startswith("> Status: ") for line in lines))
        table = [line for line in lines if line.startswith("|")]
        self.assertEqual([len(cells(line)) for line in table], [6, 6, 6])
        self.assertEqual(table[-1], ROW)

    def test_repeated_capture_appends_once(self):
        failure.append_index(str(self.index), ROW)
        self.assertFalse(failure.append_index(str(self.index), ROW))
        self.assertEqual(self.index.read_text().count(ROW), 1)


if __name__ == "__main__":
    unittest.main()
