#!/usr/bin/env python3
"""Submit work or operate the shared dev integration queue.

The PR is the cross-session handoff. Git, land-dev, and gate-state remain the
owners of merged history, publication, and validation. This command records
only queue membership and recovery state; it never invents a green receipt.
"""

from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import uuid

from agent_context import read_context, set_context

READY = "integration-ready"
START = "<!-- x2c-integration:start -->"
END = "<!-- x2c-integration:end -->"
SHA = re.compile(r"[0-9a-f]{40}\Z")
FINAL = {"landed", "parked"}
GENERATED_DOCS = {"site/public/llms.txt", "site/public/llms-full.txt"}


class WaitExpired(Exception):
    pass


def interrupt_wait(_signal, _frame):
    raise KeyboardInterrupt("wait interrupted")


def command(args, root, *, input=None, check=True, deadline=None):
    options = {"cwd": root, "text": True, "stdout": subprocess.PIPE,
               "stderr": subprocess.PIPE}
    if deadline is None:
        result = subprocess.run(args, input=input, **options)
    else:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise WaitExpired("wait I/O budget expired before " + str(args[0]))
        with subprocess.Popen(args, start_new_session=True, **options) as process:
            try:
                stdout, stderr = process.communicate(input, timeout=remaining)
            except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
                # Git's SSH/credential helpers can retain its output pipes.
                # Stop this wait's process group before draining those pipes.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.communicate()
                if isinstance(error, KeyboardInterrupt):
                    raise
                raise WaitExpired("wait I/O budget expired during " + str(args[0]))
            result = subprocess.CompletedProcess(args, process.returncode,
                                                 stdout, stderr)
    if check and result.returncode:
        raise RuntimeError(f"{args[0]} failed: " +
                           (result.stderr or result.stdout).strip())
    return result


def git(root, *args, deadline=None):
    return command(["git", *args], root, deadline=deadline).stdout.strip()


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp-" + uuid.uuid4().hex)
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    os.replace(temporary, path)


def output(value):
    print(json.dumps(value, indent=2))


def revision(value):
    if not isinstance(value, str) or not SHA.fullmatch(value):
        raise ValueError("revision must be a full 40-character commit SHA")
    return value


def submission_contact(value):
    if not isinstance(value, dict) or set(value) != {"transport", "bag", "peer"}:
        raise ValueError("contact requires only transport, bag, and peer")
    if value["transport"] != "postbag":
        raise ValueError("contact transport must be postbag")
    for field in ("bag", "peer"):
        name = value[field]
        if not isinstance(name, str) or not re.fullmatch(r"[a-z][a-z0-9-]{0,15}", name):
            raise ValueError("contact names require 1-16 lowercase letters, "
                             "digits, or hyphens, starting with a letter")
    return value


def metadata(body):
    if body.count(START) != 1 or body.count(END) != 1:
        raise ValueError("one integration submission block is required")
    text = body.split(START, 1)[1].split(END, 1)[0].strip()
    if text.startswith("```json\n") and text.endswith("```"):
        text = text[8:-3]
    value = json.loads(text)
    if not isinstance(value, dict) or value.get("version") != 1:
        raise ValueError("unsupported submission version")
    if "contact" in value:
        submission_contact(value["contact"])
    revision(value["base"])
    revision(value["head"])
    if not isinstance(value["dependencies"], list):
        raise ValueError("dependencies must be a list")
    for dependency in value["dependencies"]:
        if not isinstance(dependency, dict):
            raise ValueError("dependency must name a PR and revision")
        if type(dependency["pr"]) is not int or dependency["pr"] < 1:
            raise ValueError("dependency PR must be a positive number")
        revision(dependency["head"])
    evidence = value["evidence"]
    if not isinstance(evidence, list) or not evidence:
        raise ValueError("focused-check evidence is required")
    for item in evidence:
        if not isinstance(item, dict) or not all(
                   isinstance(item.get(key), str) and item[key].strip()
                   for key in ("command", "result")):
            raise ValueError("each check needs a command and result")
    return value


class Queue:
    def __init__(self, root, *, deadline=None):
        self.root = root
        self.directory = root / "debug" / "integration"
        self.repo = None
        self.deadline = deadline
        self.observed_pending = []

    def repository(self):
        if self.repo is None:
            self.repo = command(
                ["gh", "repo", "view", "--json", "nameWithOwner", "--jq",
                 ".nameWithOwner"], self.root,
                deadline=self.deadline).stdout.strip()
            if not re.fullmatch(r"[\w.-]+/[\w.-]+", self.repo):
                raise ValueError("cannot identify the GitHub repository")
        return self.repo

    def api(self, suffix, *, data=None, pages=False):
        args = ["gh", "api", f"repos/{self.repository()}/{suffix}"]
        if pages:
            args += ["--paginate", "--slurp"]
        if data is not None:
            args += ["--method", "POST", "--input", "-"]
        result = command(args, self.root,
                         input=None if data is None else json.dumps(data),
                         deadline=self.deadline)
        value = json.loads(result.stdout)
        return [item for page in value for item in page] if pages else value

    def patch_pull(self, number, body):
        command(["gh", "api", f"repos/{self.repository()}/pulls/{number}",
                 "--method", "PATCH", "--input", "-"], self.root,
                input=json.dumps({"body": body}))

    def remove_ready(self, number):
        # A label's absence is expected; unrelated API failures are not.
        result = command(
            ["gh", "api", f"repos/{self.repository()}/issues/{number}/labels/"
             f"{READY}", "--method", "DELETE"], self.root, check=False)
        if result.returncode and "HTTP 404" not in result.stderr:
            raise RuntimeError(result.stderr.strip())

    def add_ready(self, number):
        label = command(
            ["gh", "api", f"repos/{self.repository()}/labels/{READY}"],
            self.root, check=False)
        if label.returncode:
            if "HTTP 404" not in label.stderr:
                raise RuntimeError(label.stderr.strip())
            self.api("labels", data={"name": READY, "color": "0e8a16",
                                     "description": "Ready for integration"})
        self.api(f"issues/{number}/labels", data={"labels": [READY]})

    def pull(self, number):
        return self.api(f"pulls/{number}")

    def entry(self, pull):
        if pull["state"] != "open" or pull["draft"]:
            raise ValueError("PR must be open and non-draft")
        if pull["base"]["ref"] != "dev":
            raise ValueError("PR must target dev")
        head_repo = pull["head"].get("repo") or {}
        if head_repo.get("full_name", "").lower() != self.repository().lower():
            raise ValueError("PR must use a branch in this repository")
        if READY not in {item["name"] for item in pull["labels"]}:
            raise ValueError("readiness was withdrawn")
        value = metadata(pull.get("body") or "")
        if pull["head"]["sha"] != value["head"]:
            raise ValueError("PR head changed; submit the new revision")
        return {**value, "number": pull["number"], "url": pull["html_url"]}

    def records(self):
        return [json.loads(p.read_text()) for p in
                sorted(self.directory.glob("*/batch.json"))]

    def active(self):
        active = [r for r in self.records() if r["state"] not in FINAL]
        if len(active) > 1:
            raise RuntimeError("multiple active batches need reconciliation")
        return active[0] if active else None

    def path(self, identifier):
        if not re.fullmatch(r"[A-Za-z0-9-]+", identifier):
            raise ValueError("invalid batch ID")
        return self.directory / identifier / "batch.json"

    def read(self, identifier):
        record = json.loads(self.path(identifier).read_text())
        if record["repository"] != self.repository():
            raise ValueError("batch belongs to another repository")
        return record

    def save(self, record):
        atomic_json(self.path(record["id"]), record)

    @contextlib.contextmanager
    def lock(self):
        common = Path(git(self.root, "rev-parse", "--git-common-dir"))
        if not common.is_absolute():
            common = self.root / common
        with (common / "integration.lock").open("a+") as stream:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                stream.seek(0)
                holder = stream.read().strip() or "unknown"
                raise RuntimeError(f"another coordinator command is active (pid {holder})")
            stream.seek(0)
            stream.truncate()
            stream.write(str(os.getpid()))
            stream.flush()
            yield

    def integrator(self):
        context = read_context(self.root)
        if context != {"role": "integrator", "delivery": "direct"}:
            raise ValueError("set context --role integrator --delivery direct")

    def fetch_dev(self):
        git(self.root, "fetch", "origin", "dev", deadline=self.deadline)
        return git(self.root, "rev-parse", "origin/dev", deadline=self.deadline)

    def ancestor(self, commit, tip, root=None):
        return command(["git", "merge-base", "--is-ancestor", commit, tip],
                       root or self.root, check=False,
                       deadline=self.deadline).returncode == 0

    def open_pulls(self):
        return self.api("pulls?state=open&base=dev&per_page=100", pages=True)

    def ready(self, pulls=None):
        pulls = self.open_pulls() if pulls is None else pulls
        self.observed_entries = []
        held = {(pr["number"], pr["head"]) for record in self.records()
                if record["state"] == "parked"
                for pr in record["prs"]
                if not any(released["number"] == pr["number"] and
                           released["head"] == pr["head"]
                           for released in record.get("released_prs", []))}
        ready, pending = [], []
        self.observed_pending = pending
        for pull in pulls:
            if READY not in {label["name"] for label in pull["labels"]}:
                continue
            try:
                entry = self.entry(pull)
                if (entry["number"], entry["head"]) in held:
                    self.observed_entries.append(entry)
                    raise ValueError("revision is held after a parked batch")
                events = self.api(
                    f"issues/{entry['number']}/events?per_page=100", pages=True)
                labels = [e["created_at"] for e in events
                          if e["event"] == "labeled" and
                          (e.get("label") or {}).get("name") == READY]
                if not labels:
                    raise ValueError("readiness event is unavailable")
                entry["ready_at"] = max(labels)
                self.observed_entries.append(entry)
                ready.append(entry)
            except (ValueError, KeyError, TypeError) as error:
                pending.append({"number": pull["number"], "reason": str(error)})
        return sorted(ready, key=lambda e: (e["ready_at"], e["number"])), pending

    def select(self, entries, base, args):
        available = {e["number"]: e for e in entries}
        selected, errors = [], []
        capacity = args.max_batch if args.max_batch is not None else len(entries)

        def include(entry, chain, group):
            number = entry["number"]
            if number in chain:
                raise ValueError("dependency cycle")
            if number in {e["number"] for e in selected + group}:
                return
            for dependency in entry["dependencies"]:
                if self.ancestor(dependency["head"], base):
                    continue
                other = available.get(dependency["pr"])
                if other is None or other["head"] != dependency["head"]:
                    raise ValueError(f"waiting for dependency #{dependency['pr']}")
                include(other, chain | {number}, group)
            group.append(entry)

        explicit = getattr(args, "prs", None)
        for number in explicit or [e["number"] for e in entries]:
            group = []
            try:
                if number not in available:
                    raise ValueError("PR is not eligible")
                include(available[number], set(), group)
                if len(selected) + len(group) > capacity:
                    raise ValueError("dependency group exceeds remaining batch capacity")
                selected.extend(group)
            except ValueError as error:
                errors.append({"number": number, "reason": str(error)})
        if explicit and errors:
            raise ValueError("explicit batch cannot be assembled: " +
                             "; ".join(f"#{e['number']}: {e['reason']}"
                                       for e in errors))
        if selected and not args.flush and not explicit:
            oldest = dt.datetime.fromisoformat(
                min(e["ready_at"] for e in selected).replace("Z", "+00:00"))
            age = (dt.datetime.now(dt.timezone.utc) - oldest).total_seconds()
            if len(selected) < (args.max_batch or 5) and age < args.window:
                return [], errors, max(0, args.window - age)
        return selected, errors, 0

    def exclusions(self, path):
        if not path:
            return []
        values = json.loads(Path(path).read_text())
        if not isinstance(values, list):
            raise ValueError("exclusions must be a JSON list")
        for item in values:
            if (not isinstance(item, dict) or type(item.get("number")) is not int or
                    not isinstance(item.get("reason"), str) or
                    not item["reason"].strip()):
                raise ValueError("each exclusion needs number, head, and concrete reason")
            revision(item["head"])
        return values

    def selection(self, record, entries, pending, exclusions):
        selected = {(e["number"], e["head"]) for e in record["prs"]}
        reasons = {(e["number"], e["head"]): e["reason"]
                   for e in exclusions}
        # Dependency failures are established by the existing selector.
        options = argparse.Namespace(prs=None, max_batch=None, flush=True)
        _, blocked, _ = self.select(entries, record["base"], options)
        blocked = {e["number"]: e["reason"] for e in blocked}
        omitted = []
        for entry in self.observed_entries:
            key = entry["number"], entry["head"]
            if key not in selected:
                omitted.append({"number": key[0], "head": key[1],
                                "reason": reasons.get(key, blocked.get(key[0]))})
        decision = {"observed_at": now(), "eligible": self.observed_entries,
                    "selected": record["prs"], "excluded": omitted,
                    "pending": pending}
        record["selection"] = decision
        self.save(record)
        missing = [str(e["number"]) for e in omitted if not e["reason"]]
        if missing:
            raise ValueError("regroup compatible submissions or supply pinned "
                             "exclusions with --exclude-file for PRs " + ", ".join(missing))
        return decision

    def submit(self, args):
        contact = submission_contact(
            json.loads(Path(args.contact_file).read_text())
        ) if args.contact_file else None
        context = read_context(self.root)
        if not context or context["delivery"] != "pr":
            raise ValueError("select PR delivery with the context command first")
        if git(self.root, "status", "--porcelain"):
            raise ValueError("commit the authored changes before submission")
        pull = self.pull(args.pr)
        if (pull["state"] != "open" or pull["draft"] or
                pull["base"]["ref"] != "dev" or
                (pull["head"].get("repo") or {}).get("full_name", "").lower()
                != self.repository().lower()):
            raise ValueError("submit an open non-draft same-repository dev PR")
        head = git(self.root, "rev-parse", "HEAD")
        if pull["head"]["sha"] != head:
            raise ValueError("local HEAD must match the pushed PR head")
        base = revision(args.base)
        if not self.ancestor(base, head):
            raise ValueError("recorded starting revision is not an ancestor")
        dependencies = []
        for item in args.depends_on:
            number, sha = item.split(":", 1)
            dependencies.append({"pr": int(number), "head": revision(sha)})
        value = {"version": 1, "base": base, "head": head,
                 "dependencies": dependencies,
                 "evidence": json.loads(Path(args.evidence_file).read_text()),
                 "notes": args.notes}
        if contact is not None:
            value["contact"] = contact
        block = START + "\n```json\n" + json.dumps(value, indent=2) + \
            "\n```\n" + END
        metadata(block)
        body = pull.get("body") or ""
        if START in body or END in body:
            if body.count(START) != 1 or body.count(END) != 1:
                raise ValueError("ambiguous existing submission block")
            before, rest = body.split(START, 1)
            _, after = rest.split(END, 1)
            body = before + block + after
        else:
            body = body.rstrip() + "\n\n" + block
        self.remove_ready(args.pr)
        self.patch_pull(args.pr, body)
        if self.pull(args.pr)["head"]["sha"] != head:
            raise ValueError("PR changed during submission; readiness not applied")
        self.add_ready(args.pr)
        output({"submitted": args.pr, "head": head, "url": pull["html_url"]})

    def prepare(self, args):
        self.integrator()
        if args.retry:
            record = self.read(args.retry)
            if record["state"] != "parked":
                raise ValueError("only a parked batch can be retried")
            if record.get("released_prs"):
                raise ValueError("batch holds were released; prepare a new batch")
            if self.active():
                raise ValueError("finish or park the active batch before retrying")
            if args.prs and set(args.prs) != {
                    entry["number"] for entry in record["prs"]}:
                raise ValueError("retry retains the batch's frozen PR selection")
            for entry in record["prs"]:
                current = self.entry(self.pull(entry["number"]))
                if current["head"] != entry["head"]:
                    raise ValueError("PR revision changed; prepare a new batch")
            record.pop("retry", None)
            record["state"] = "preparing"
            self.save(record)
            return self.assemble(record)
        record = self.active()
        if record:
            return self.assemble(record)
        base = self.fetch_dev()
        entries, pending = self.ready()
        selected, blocked, wait = self.select(entries, base, args)
        if not selected:
            output({"ready": [], "pending": pending + blocked,
                    "wait_seconds": wait})
            return
        identifier = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ-")
        identifier += uuid.uuid4().hex[:8]
        directory = self.directory / identifier
        record = {"version": 1, "id": identifier,
                  "repository": self.repository(), "base": base,
                  "prs": selected, "branch": "codex/integration-" + identifier,
                  "worktree": str(directory / "tree"), "state": "preparing",
                  "merged": [], "attempts": [], "started_at": now(),
                  "exclusions": self.exclusions(args.exclude_file),
                  "queue_snapshot": {"observed_at": now(),
                                     "eligible": self.observed_entries,
                                     "pending": pending + blocked}}
        self.save(record)
        return self.assemble(record)

    def assemble(self, record):
        if record["state"] not in {"preparing", "needs-attention"}:
            output(record)
            return
        tree = Path(record["worktree"])
        try:
            if not tree.exists():
                for entry in record["prs"]:
                    ref = f"refs/x2c/integration/{record['id']}/pr-{entry['number']}"
                    git(self.root, "fetch", "origin",
                        f"refs/pull/{entry['number']}/head:{ref}")
                    if git(self.root, "rev-parse", ref) != entry["head"]:
                        raise ValueError(f"PR #{entry['number']} changed before freeze")
                    if not self.ancestor(entry["base"], entry["head"]):
                        raise ValueError("submitted base is not an ancestor of head")
                git(self.root, "worktree", "add", "-b", record["branch"],
                    str(tree), record["base"])
            set_context(tree, "integrator", "direct")
            if git(tree, "status", "--porcelain"):
                raise ValueError("resolve and commit the candidate's pending changes")
            for entry in record["prs"]:
                if not self.ancestor(entry["head"], "HEAD", tree):
                    git(tree, "merge", "--no-ff", "--no-edit", entry["head"])
                if entry["number"] not in record["merged"]:
                    record["merged"].append(entry["number"])
                    self.save(record)
            record.update(state="review", candidate=git(tree, "rev-parse", "HEAD"))
            record.pop("reason", None)
        except (RuntimeError, ValueError) as error:
            record.update(state="needs-attention", reason=str(error))
        self.save(record)
        output(record)

    def release(self, args):
        self.integrator()
        record = self.read(args.batch)
        if record["state"] != "parked":
            raise ValueError("only parked batch holds can be released")
        selected = set(args.prs)
        if not selected <= {entry["number"] for entry in record["prs"]}:
            raise ValueError("selected PR is not in the frozen batch")
        exclusions = self.exclusions(args.exclude_file)
        prior = {e["number"] for e in record.get("released_prs", [])}
        retained = [e for e in record["prs"] if e["number"] not in selected | prior]
        reasons = {(e["number"], e["head"]): e["reason"] for e in exclusions}
        if any((e["number"], e["head"]) not in reasons for e in retained):
            raise ValueError("release all unaffected revisions together; name each "
                             "retained blocker in --exclude-file")
        held = {(e["number"], e["head"]) for e in retained}
        for entry in record["prs"]:
            if entry["number"] in selected and any(
                    (d["pr"], d["head"]) in held for d in entry["dependencies"]):
                raise ValueError("released revision depends on a retained blocker")
        record["retained"] = [{**e, "reason": reasons[e["number"], e["head"]]}
                              for e in retained]
        released = record.setdefault("released_prs", [])
        for entry in record["prs"]:
            if entry["number"] in selected and not any(
                    prior["number"] == entry["number"] and
                    prior["head"] == entry["head"] for prior in released):
                released.append({**entry, "released_at": now(),
                                 "reason": args.reason})
        self.save(record)
        output(record)

    def reconcile(self, record, base):
        gated = record.get("gated")
        if gated and self.ancestor(gated, base):
            record.update(state="landed", landed=gated, landed_at=now())
            record.pop("reason", None)
            self.save(record)
            for entry in record["prs"]:
                pull = self.pull(entry["number"])
                if pull["head"]["sha"] == entry["head"]:
                    self.remove_ready(entry["number"])
            record["reconciled"] = True
            self.save(record)
            return True
        return False

    def gate_for(self, tree, base):
        raw = command(["git", "diff", "--raw", "-z", "--no-renames", base,
                       "HEAD"], tree).stdout.split("\0")
        for i in range(0, len(raw) - 1, 2):
            modes, path = raw[i].split(), raw[i + 1]
            before, after = modes[0][1:], modes[1]
            if not (before in {"000000", "100644"} and
                    after in {"000000", "100644"} and
                    (path in GENERATED_DOCS or
                     path in {"AGENTS.md", "README.md"} or
                     (path.endswith(".md") and
                      path.startswith(("agents/", "docs/", "plans/"))))):
                return "agent-pr-check"
        return "doc-check"

    def recover_gate(self, record):
        if record["state"] not in {"gating", "needs-attention", "publishing"}:
            return False
        if not record.get("gate") or not record.get("reviewed"):
            return False
        tree = Path(record["worktree"])
        if not all(self.ancestor(e["head"], "HEAD", tree) for e in record["prs"]):
            return False
        try:
            review = json.loads((tree / "debug" / "land-dev-review.json").read_text())
        except FileNotFoundError:
            review = {}
        head = git(tree, "rev-parse", "HEAD")
        proof = command([str(tree / "tools" / "gate-state.py"), "check",
                         record["gate"]], tree, check=False)
        if proof.returncode:
            return False
        if (review.get("candidate") != head or
                review.get("upstream") != record["base"] or
                review.get("gate") != record["gate"] or
                git(tree, "status", "--porcelain")):
            # land-dev owns generated commits and receipts. Recovery cannot build.
            log = self.path(record["id"]).parent / f"recovery-{uuid.uuid4().hex}.log"
            with log.open("w") as stream:
                result = subprocess.run([
                    str(self.root / "tools" / "land-dev"), "--recover-reviewed",
                    "--expected-dev", record["base"], "--gate", record["gate"],
                    "refresh bootstrap for integration batch"], cwd=tree,
                    stdout=stream, stderr=subprocess.STDOUT)
            record.setdefault("recoveries", []).append(
                {"at": now(), "log": str(log), "returncode": result.returncode})
            self.save(record)
            if result.returncode:
                raise ValueError("proof passed but recovery failed; see " + str(log))
            head = git(tree, "rev-parse", "HEAD")
        record.update(state="gated", gated=head)
        record.pop("reason", None)
        self.save(record)
        return True

    def land(self, args):
        self.integrator()
        record = self.read(args.batch)
        upstream = self.fetch_dev()
        if self.recover_gate(record):
            output(record)
            return
        if self.reconcile(record, upstream):
            output(record)
            return
        if record["state"] == "parked":
            raise ValueError("parked batch requires explicit retry")
        tree = Path(record["worktree"])
        if git(tree, "status", "--porcelain"):
            raise ValueError("candidate must be committed and clean")
        if not all(self.ancestor(e["head"], "HEAD", tree) for e in record["prs"]):
            raise ValueError("not all pinned heads are incorporated")
        if upstream != record["base"]:
            git(tree, "merge", "--no-edit", upstream)
            record.update(base=upstream, state="review",
                          candidate=git(tree, "rev-parse", "HEAD"),
                          reason="dev advanced; review the combined diff again")
            record.pop("gated", None)
            self.save(record)
            output(record)
            return
        # One paginated snapshot replaces one request per frozen PR. A missing
        # entry is closed or no longer targets dev, and cannot be published.
        pulls = {pull["number"]: pull for pull in self.open_pulls()}
        for entry in record["prs"]:
            pull = pulls.get(entry["number"])
            if pull is None:
                raise ValueError(f"PR #{entry['number']} is no longer open on dev")
            current = self.entry(pull)
            if current["head"] != entry["head"]:
                raise ValueError("PR revision changed; park and select a new batch")
        head = git(tree, "rev-parse", "HEAD")
        gate = self.gate_for(tree, upstream)
        args_land = [str(tree / "tools" / "land-dev"),
                     "--expected-dev", upstream, "--gate", gate]
        if args.publish:
            if record.get("gated") != head or record["state"] != "gated":
                raise ValueError("review and gate this candidate before publishing")
            if record.get("gate") != gate:
                raise ValueError("gate selection changed")
            args_land += ["--publish-reviewed", head]
        else:
            if (record["state"] == "gated" and record.get("gated") == head and
                    record.get("gate") == gate and not command(
                        [str(tree / "tools" / "gate-state.py"), "check", gate],
                        tree, check=False).returncode):
                output(record)
                return
            entries, pending = self.ready(list(pulls.values()))
            exclusions = record.get("exclusions", []) + self.exclusions(args.exclude_file)
            for parked in self.records():
                if parked["state"] == "parked":
                    exclusions += parked.get("retained", [])
            exclusions = list({(e["number"], e["head"]): e
                               for e in exclusions}.values())
            decision = self.selection(record, entries, pending, exclusions)
            print("integration selection: " + json.dumps({
                "observed_at": decision["observed_at"],
                "selected": [{"number": e["number"], "head": e["head"]}
                             for e in record["prs"]],
                "excluded": decision["excluded"]}), file=sys.stderr, flush=True)
            record["exclusions"] = exclusions
            record.update(reviewed=head, gate=gate)
            args_land += ["--review-stop", "refresh bootstrap for integration batch"]
        attempt = {"phase": "publish" if args.publish else "gate",
                   "started_at": now(),
                   "log": str(self.path(record["id"]).parent /
                              f"attempt-{len(record['attempts']) + 1}.log")}
        record["attempts"].append(attempt)
        record["state"] = "publishing" if args.publish else "gating"
        self.save(record)
        started = time.monotonic()
        with Path(attempt["log"]).open("w") as stream:
            result = subprocess.run(args_land, cwd=tree, stdout=stream,
                                    stderr=subprocess.STDOUT)
        attempt.update(elapsed_seconds=time.monotonic() - started,
                       returncode=result.returncode)
        if result.returncode:
            record.update(state="needs-attention",
                          reason=f"publication failed; see {attempt['log']}")
        elif args.publish:
            self.save(record)
            self.reconcile(record, self.fetch_dev())
        else:
            record.update(state="gated", gated=git(tree, "rev-parse", "HEAD"))
            record.pop("reason", None)
        self.save(record)
        output(record)

    def retire(self, args):
        self.integrator()
        record = self.read(args.batch)
        if record.get("retired_at"):
            output(record)
            return
        base = self.fetch_dev()
        replacement = self.read(args.replacement) if args.replacement else None
        if replacement and (replacement["state"] != "landed" or
                            not replacement.get("reconciled") or
                            not self.ancestor(replacement["landed"], base)):
            raise ValueError("replacement must be landed and reconciled")
        if record["state"] == "landed":
            if not record.get("reconciled") or not self.ancestor(record["landed"], base):
                raise ValueError("confirm publication and reconciliation before retirement")
        elif record["state"] == "parked" and replacement:
            replacements = {e["number"] for e in replacement["prs"]}
            if any(e["number"] not in replacements and not self.ancestor(e["head"], base)
                   for e in record["prs"]):
                raise ValueError("parked revisions still own unresolved holds")
        else:
            raise ValueError("only reconciled landed or resolved parked candidates can retire")
        tree = Path(record["worktree"])
        expected = self.path(record["id"]).parent / "tree"
        if tree != expected or not tree.exists():
            raise ValueError("candidate path does not match its batch")
        if git(tree, "status", "--porcelain"):
            raise ValueError("candidate has pending changes")
        head = git(tree, "rev-parse", "HEAD")
        if git(tree, "branch", "--show-current") != record["branch"]:
            raise ValueError("candidate branch changed; preserve its history first")
        if not self.ancestor(head, base) and not (replacement and args.archive_repairs):
            raise ValueError("candidate contains unique unpublished commits; preserve repairs first "
                             "with a landed replacement and --archive-repairs")
        ignored = git(tree, "ls-files", "--others", "--ignored", "--exclude-standard")
        unexpected = [p for p in ignored.splitlines()
                      if not p.startswith(("debug/", "builds/", "unittest/build/")) and
                      not ("__pycache__" in Path(p).parts and p.endswith(".pyc"))]
        if unexpected:
            raise ValueError("preserve ignored files outside build outputs: " + ", ".join(unexpected))
        retirement = {"reason": args.reason, "replacement": args.replacement,
                      "head": head, "eligible_at": now(), "worktree": str(tree)}
        record["retirement"] = retirement
        self.save(record)
        if args.apply:
            # Archive diagnostics and pinned history outside the disposable tree.
            import shutil
            destination = expected.parent / "retained-debug"
            if (tree / "debug").exists():
                shutil.copytree(tree / "debug", destination, dirs_exist_ok=True,
                                symlinks=True)
            command(["git", "bundle", "create", str(expected.parent / "candidate.bundle"),
                     record["branch"]], self.root)
            command(["git", "bundle", "verify", str(expected.parent / "candidate.bundle")],
                    self.root)
            patch = command(["git", "diff", "--binary", record["base"], head], tree)
            (expected.parent / "candidate.patch").write_text(patch.stdout)
            git(self.root, "worktree", "remove", str(tree))
            record["retired_at"] = now()
            self.save(record)
        output(record)

    def status(self):
        entries, pending = self.ready()
        output({"repository": self.repository(), "ready": entries,
                "pending": pending, "active": self.active(),
                "batches": self.records()})

    def wait(self, args):
        self.integrator()
        if self.deadline is None:
            self.deadline = time.monotonic() + (args.timeout or 60)
        try:
            while True:
                active = self.active()
                if active:
                    output({"active": active, "timed_out": False})
                    return
                base = self.fetch_dev()
                entries, pending = self.ready()
                selected, blocked, wait = self.select(entries, base, args)
                self.observed_pending = pending + blocked
                timed_out = time.monotonic() >= self.deadline
                if selected or args.timeout == 0 or timed_out:
                    output({"ready": [e["number"] for e in selected],
                            "pending": self.observed_pending,
                            "wait_seconds": wait, "timed_out": timed_out})
                    return
                time.sleep(min(10, max(0, self.deadline - time.monotonic())))
        except WaitExpired as error:
            output({"ready": [], "pending": self.observed_pending,
                    "timed_out": True, "reason": str(error)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    commands = parser.add_subparsers(dest="operation", required=True)
    context = commands.add_parser("context", help="select this worktree's delivery")
    context.add_argument("--role", choices=["individual", "orchestrator",
                                           "integrator", "worker"], required=True)
    context.add_argument("--delivery", choices=["direct", "pr", "private"],
                         required=True)
    submit = commands.add_parser("submit", help="enroll an existing ready dev PR")
    submit.add_argument("--pr", type=int, required=True)
    submit.add_argument("--base", required=True)
    submit.add_argument("--evidence-file", required=True)
    submit.add_argument("--contact-file", help="optional Postbag contact JSON "
                        "with transport, bag, and peer")
    submit.add_argument("--depends-on", action="append", default=[])
    submit.add_argument("--notes", default="")
    commands.add_parser("status", help="show readiness and durable batch state")
    for name in ("prepare", "wait"):
        operation = commands.add_parser(name)
        operation.add_argument("--max-batch", type=int,
                               help="explicit cap; default freezes the ready backlog")
        operation.add_argument("--window", type=float, default=300)
        operation.add_argument("--flush", action="store_true")
        if name == "prepare":
            operation.add_argument("--prs", type=int, nargs="+")
            operation.add_argument("--exclude-file", help="pinned exclusions JSON")
            operation.add_argument("--retry", help="resume a parked candidate "
                                   "with its original pinned PRs and repairs")
        else:
            operation.add_argument(
                "--timeout", type=float, default=60,
                help="overall wait/I/O budget (0-60 seconds); 0 polls once "
                     "with a maximum 60-second I/O budget")
    land = commands.add_parser("land", help="gate, or publish a reviewed gated batch")
    land.add_argument("batch")
    land.add_argument("--publish", action="store_true")
    land.add_argument("--exclude-file", help="pinned exclusions JSON")
    park = commands.add_parser("park", help="retain a candidate and hold its revisions")
    park.add_argument("batch")
    park.add_argument("--reason", default="parked for diagnosis")
    release = commands.add_parser(
        "release", help="release selected parked holds for a new batch")
    release.add_argument("batch")
    release.add_argument("--prs", type=int, nargs="+", required=True)
    release.add_argument("--reason", default="released for reselection")
    release.add_argument("--exclude-file", help="JSON reasons for every retained revision")
    retire = commands.add_parser("retire", help="inspect retirement eligibility; --apply removes candidate")
    retire.add_argument("batch")
    retire.add_argument("--reason", required=True)
    retire.add_argument("--replacement", help="landed replacement batch for a resolved failure")
    retire.add_argument("--apply", action="store_true")
    retire.add_argument("--archive-repairs", action="store_true",
                        help="preserve unique candidate history with a landed replacement")
    args = parser.parse_args()
    try:
        deadline = None
        if args.operation == "wait":
            if not 0 <= args.timeout <= 60:
                raise ValueError("wait timeout must be between 0 and 60 seconds")
            if (args.max_batch is not None and args.max_batch < 1) or args.window < 0:
                raise ValueError("batch size must be positive and window nonnegative")
            signal.signal(signal.SIGTERM, interrupt_wait)
            deadline = time.monotonic() + (args.timeout or 60)
        root = Path(git(args.root.resolve(), "rev-parse", "--show-toplevel",
                        deadline=deadline))
        queue = Queue(root, deadline=deadline)
        if args.operation == "context":
            set_context(root, args.role, args.delivery)
            output(read_context(root))
        elif args.operation == "wait":
            queue.wait(args)
        elif args.operation == "status":
            queue.status()
        elif args.operation == "submit":
            queue.submit(args)
        else:
            with queue.lock():
                if args.operation == "prepare":
                    if (args.max_batch is not None and args.max_batch < 1) or args.window < 0:
                        raise ValueError("batch size must be positive and window nonnegative")
                    queue.prepare(args)
                elif args.operation == "land":
                    queue.land(args)
                elif args.operation == "release":
                    queue.release(args)
                elif args.operation == "retire":
                    queue.retire(args)
                elif args.operation == "park":
                    queue.integrator()
                    record = queue.read(args.batch)
                    if record["state"] == "landed":
                        raise ValueError("landed batches cannot be parked")
                    record.update(state="parked", reason=args.reason)
                    queue.save(record)
                    output(record)
        return 0
    except WaitExpired as error:
        output({"ready": [], "pending": [], "timed_out": True,
                "reason": str(error)})
        return 0
    except (OSError, RuntimeError, ValueError, KeyError, TypeError,
            KeyboardInterrupt) as error:
        print(f"integrate-dev: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
