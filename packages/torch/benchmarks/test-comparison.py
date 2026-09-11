#!/usr/bin/env python3
"""Optional comparison acceptance regressions; no training or native build."""

import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import torch

import common
import report
import run


class TensorComparison(unittest.TestCase):
    def verdict(self, left, right, name="values"):
        return common.compare_tensors({name: left}, {name: right})[0][3]

    def test_small_element_cannot_borrow_large_elements_tolerance(self):
        self.assertEqual(self.verdict(torch.tensor([1e6, 1.0]),
                                      torch.tensor([1e6, 2.0])), "over")
        self.assertEqual(self.verdict(torch.tensor([1e6, 1.0]),
                                      torch.tensor([1e6, 1.00001])), "ok")

    def test_integer_and_metadata_values_are_exact(self):
        for name, left, right in (
                ("values", torch.tensor([10000, 2]), torch.tensor([10001, 2])),
                ("values", torch.tensor([2**62]), torch.tensor([2**62 + 1])),
                ("meta.version", torch.tensor([1.0]), torch.tensor([1.00001]))):
            with self.subTest(name=name, left=left):
                self.assertEqual(self.verdict(left, right, name), "different")

    def test_structure_and_nonfinite_values(self):
        for left, right, verdict in (
                (torch.tensor([1]), torch.tensor([1.0]), "dtype"),
                (torch.tensor([1.0]), torch.tensor([[1.0]]), "shape"),
                (torch.tensor([float("nan")]), torch.tensor([0.0]), "non-finite")):
            self.assertEqual(self.verdict(left, right), verdict)
        self.assertEqual(common.compare_tensors({}, {})[0][3], "empty")
        self.assertEqual(common.compare_tensors({"x": torch.tensor(1)}, {})[0][3],
                         "missing")


class CheckAcceptance(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="torch-check-test-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        for key, directory in (("BINARIES", "bin"), ("OUTPUTS", "out"),
                               ("LOGS", "logs")):
            path = self.root / directory
            path.mkdir()
            owner = patch.object(common, key, str(path))
            owner.start()
            self.addCleanup(owner.stop)
        (Path(common.BINARIES) / "tabular").touch()
        self.records = {
            "interop_threads": 1, "probe_loss": 0.3,
            "untrained_val_mse": 0.4, "mean_val_mse": 0.3,
            "trained_val_mse": 0.03, "explicit_val_mse": 0.03,
            "resumed_val_mse": 0.03, "predict1_checksum": 1,
            "predict32_checksum": 32, "predict256_checksum": 256,
        }
        self.config = {
            "cfg_features": 128, "cfg_hidden1": 256, "cfg_hidden2": 128,
            "cfg_targets": 8, "cfg_batch": 128, "cfg_updates": 1024,
            "cfg_lr": 0.001, "cfg_artifact_version": 1, "threads": 1,
        }
        self.x_records = self.records | self.config
        self.p_records = dict(self.records)
        self.checkpoints = {
            f"tabular-{language}-{stage}.pt": {"weight": torch.tensor([1e6, 1.0])}
            for language in ("x2c", "python") for stage in ("step1", "final")}

    def launch(self, *args, **kwargs):
        for name, values in self.checkpoints.items():
            torch.save(values, common.output(name))
        return {name: common.Result(values, {}, [], 0, "", 0)
                for name, values in (("x2c", self.x_records),
                                     ("python", self.p_records))}

    def check(self):
        with (patch.object(run, "both", self.launch),
              contextlib.redirect_stdout(io.StringIO())):
            return run.check(["tabular"], 1, "test")

    def test_complete_matching_run(self):
        self.assertEqual(self.check(), 0)
        retained = self.root / "logs/test/checkpoints/tabular-x2c-step1.pt"
        self.assertTrue(retained.is_file())
        saved = common.load_tensors(str(retained))
        self.assertTrue(torch.equal(saved["weight"], torch.tensor([1e6, 1.0])))

    def test_missing_binary(self):
        (Path(common.BINARIES) / "tabular").unlink()
        self.assertEqual(self.check(), 1)

    def test_missing_timing_or_memory_binary_is_not_skipped(self):
        (Path(common.BINARIES) / "tabular").unlink()
        with self.assertRaises(RuntimeError):
            run.time_lane("tabular", "native", 1, 1, 1, "test")
        with self.assertRaises(RuntimeError):
            run.memory([1], 1, 1, "test")

    def test_missing_records_and_wrong_configuration(self):
        del self.x_records["trained_val_mse"]
        self.assertEqual(self.check(), 1)
        self.x_records = self.records | self.config | {"cfg_features": 64}
        self.assertEqual(self.check(), 1)

    def test_no_output_or_checkpoints(self):
        self.x_records = {}
        self.checkpoints = {}
        self.assertEqual(self.check(), 1)

    def test_stale_checkpoint_cannot_satisfy_current_run(self):
        missing = "tabular-x2c-step1.pt"
        torch.save(self.checkpoints.pop(missing), common.output(missing))
        self.assertEqual(self.check(), 1)

    def test_final_weight_drift_is_reported_but_first_update_drift_fails(self):
        self.checkpoints["tabular-x2c-final.pt"]["weight"][1] = 2
        self.assertEqual(self.check(), 0)
        self.checkpoints["tabular-x2c-step1.pt"]["weight"][1] = 2
        self.assertEqual(self.check(), 1)

    def test_final_checkpoint_structure_is_required(self):
        self.checkpoints["tabular-x2c-final.pt"] = {}
        self.assertEqual(self.check(), 1)

    def test_agreement_does_not_replace_task_quality(self):
        self.x_records["trained_val_mse"] = 0.5
        self.p_records["trained_val_mse"] = 0.5
        self.assertEqual(self.check(), 1)

    def test_interop_subset_needs_all_results_but_no_checkpoints(self):
        (Path(common.BINARIES) / "interop").touch()
        self.checkpoints = {}
        self.p_records = {f"chain_e{size}_o{ops}": 1.0
                          for size in (1, 64, 4096, 65536)
                          for ops in (16, 128, 512)}
        self.p_records["interop_threads"] = 1
        self.x_records = self.p_records | {"threads": 1, "cfg_artifact_version": 1}
        with (patch.object(run, "both", self.launch),
              contextlib.redirect_stdout(io.StringIO())):
            self.assertEqual(run.check(["interop"], 1, "test"), 0)
            del self.x_records["chain_e64_o16"]
            self.assertEqual(run.check(["interop"], 1, "test"), 1)

    def test_failed_tensor_comparison_is_not_reported_within_tolerance(self):
        self.checkpoints["tabular-x2c-step1.pt"]["weight"][1] = 2
        self.assertEqual(self.check(), 1)
        lines = []
        check = json.loads((self.root / "logs/test/check.json").read_text())
        report.check_section(check, lines)
        rendered = "\n".join(lines)
        self.assertNotIn("within tolerance", rendered)
        self.assertIn("failed", rendered)

    def test_legacy_comparison_does_not_imply_acceptance(self):
        lines = []
        report.check_section({"tabular": {"step1_worst_absolute": 0.0,
                                          "step1_tensors": 1}}, lines)
        self.assertIn("not revalidated", "\n".join(lines))
        self.assertNotIn("bit-identical", "\n".join(lines))


class SessionIdentity(unittest.TestCase):
    def test_session_cannot_mix_optimizer_comparisons(self):
        with (tempfile.TemporaryDirectory() as scratch,
              patch.object(common, "WORK", scratch),
              patch.object(common, "LOGS", str(Path(scratch) / "logs")),
              patch.object(common, "OUTPUTS", "unused"),
              patch.dict(os.environ)):
            self.assertEqual(run.configure_session("control", "matched"), "matched")
            control = common.OUTPUTS
            self.assertEqual(run.configure_session("control"), "matched")
            with self.assertRaises(ValueError):
                run.configure_session("control", "stock")
            self.assertEqual(run.configure_session("ordinary", "stock"), "stock")
            self.assertNotEqual(control, common.OUTPUTS)


if __name__ == "__main__":
    unittest.main()
