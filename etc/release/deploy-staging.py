#!/usr/bin/env python3
"""Commit one complete generated site with compare-and-swap, then deploy it."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import time


def api(path, method="GET", data=None):
    command = ["gh", "api", path, "--method", method]
    if data is not None:
        command += ["--input", "-"]
    result = subprocess.run(command, input=json.dumps(data) if data else None,
                            text=True, capture_output=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--expected-output", required=True)
    parser.add_argument("--repository", default="gwf/x2c-staging")
    args = parser.parse_args()
    if args.repository != "gwf/x2c-staging":
        parser.error("deployment target must be gwf/x2c-staging")
    prefix = f"repos/{args.repository}"
    head = api(f"{prefix}/git/ref/heads/main")["object"]["sha"]
    if head != args.expected_output:
        raise RuntimeError("staging changed since selection; select current output explicitly")
    commit = api(f"{prefix}/git/commits/{head}")
    old_tree = api(f"{prefix}/git/trees/{commit['tree']['sha']}")["tree"]
    archive = args.candidate / "site-staging.tar.gz"
    # The caller verifies manifest/site receipts using the trusted helper first.
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        with tarfile.open(archive, "r:gz") as tar:
            for member in tar.getmembers():
                path = Path(member.name)
                if path.is_absolute() or ".." in path.parts or not (member.isfile() or member.isdir()):
                    raise RuntimeError(f"unsafe site member: {member.name}")
            tar.extractall(root, filter="data")
        # The site helper writes paths relative to the site root.
        required = ["index.html", "release-candidate.json", "x2c-version.txt",
                    "packages/index.txt"]
        if any(not (root / path).is_file() for path in required):
            raise RuntimeError("incomplete staging site archive")
        (root / "CNAME").write_text("staging.x2c-lang.dev\n")
        entries = []
        for path in sorted(root.rglob("*")):
            if path.is_file():
                blob = api(f"{prefix}/git/blobs", "POST", {
                    "content": base64.b64encode(path.read_bytes()).decode(),
                    "encoding": "base64"})
                entries.append({"path": path.relative_to(root).as_posix(),
                                "mode": "100644", "type": "blob", "sha": blob["sha"]})
        site_tree = api(f"{prefix}/git/trees", "POST", {"tree": entries})
    # Replace public as a whole; preserve the minimal workflow and repo files.
    tree = [{key: entry[key] for key in ("path", "mode", "type", "sha")}
            for entry in old_tree if entry["path"] != "public"]
    tree.append({"path": "public", "mode": "040000", "type": "tree",
                 "sha": site_tree["sha"]})
    new_tree = api(f"{prefix}/git/trees", "POST", {"tree": tree})
    new_commit = api(f"{prefix}/git/commits", "POST", {
        "message": "deploy selected x2c candidate", "tree": new_tree["sha"],
        "parents": [head]})["sha"]
    # A concurrent commit makes this non-fast-forward, and GitHub rejects it.
    api(f"{prefix}/git/refs/heads/main", "PATCH", {"sha": new_commit, "force": False})
    receipt = {"previous_output": head, "output_sha": new_commit,
               "site_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
               "state": "output-committed"}
    receipt_path = args.candidate / "staging-deployment.json"
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    api(f"{prefix}/actions/workflows/pages.yml/dispatches", "POST", {
        "ref": "main", "inputs": {"output_sha": new_commit}})
    # Hold the source workflow's destination concurrency lock through deployment.
    for _ in range(120):
        runs = api(f"{prefix}/actions/workflows/pages.yml/runs?event=workflow_dispatch&per_page=100")
        matching = [run for run in runs["workflow_runs"]
                    if run["display_title"] == f"staging {new_commit}"]
        if matching:
            run = matching[0]
            receipt.update(run_url=run["html_url"], run_id=run["id"])
            if run["status"] == "completed":
                receipt["state"] = run["conclusion"]
                receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
                if run["conclusion"] != "success":
                    raise RuntimeError(f"staging deployment failed: {run['html_url']}")
                print(json.dumps(receipt))
                return
        time.sleep(10)
    receipt["state"] = "deployment-timeout"
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    raise RuntimeError("deployment timeout; inspect recorded commit/run before retry")


if __name__ == "__main__":
    main()
