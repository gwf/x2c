"""Optional idle-checkpoint probe; run manually with the built checkout path.

This paced workload uses the production 64 MiB growth budget. It intentionally
retains large historical snapshots and can take several minutes. Results are
observations for this workload, not a bound on one analysis or an input burst.
"""
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time


class Client:
    def __init__(self, root, directory):
        self.log = directory / "server.stderr"
        self.stderr = self.log.open("wb")
        self.process = subprocess.Popen(
            [str(root / "builds/0/libexec/x2c-lsp")], cwd=directory,
            env=dict(os.environ, X2C_CACHE_DIR=str(directory / "cache")),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=self.stderr, bufsize=0)
        self.pid = self.process.pid
        self.versions = {}
        self.messages = []
        self.next_id = 1
        self.initialize_responses = 0
        self.send("initialize", {"initializationOptions": {"arguments": []}}, 1)
        self.wait(lambda message: message.get("id") == 1)
        self.send("initialized")

    def send(self, method, params=None, identifier=None):
        message = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            message["params"] = params
        if identifier is not None:
            message["id"] = identifier
        body = json.dumps(message).encode()
        data = f"Content-Length: {len(body)}\r\n\r\n".encode() + body
        while data:
            count = self.process.stdin.write(data)
            assert count, "server stdin closed"
            data = data[count:]

    def read(self, count):
        chunks = []
        while count:
            assert select.select([self.process.stdout], [], [], 60)[0], "response timeout"
            chunk = os.read(self.process.stdout.fileno(), count)
            assert chunk, ("server ended", self.process.poll(), self.log.read_text())
            chunks.append(chunk)
            count -= len(chunk)
        return b"".join(chunks)

    def message(self):
        header = bytearray()
        while not header.endswith(b"\r\n\r\n"):
            header.extend(self.read(1))
        fields = dict(line.split(":", 1) for line in header.decode().strip().split("\r\n"))
        message = json.loads(self.read(int(fields["Content-Length"])))
        self.messages.append(message)
        if message.get("id") == 1:
            self.initialize_responses += 1
        return message

    def wait(self, predicate):
        while True:
            message = self.message()
            if predicate(message):
                return message

    def opened(self, path, text, language="x2c"):
        uri = path.as_uri()
        version = self.versions.get(uri, 0) + 1
        self.versions[uri] = version
        if version == 1:
            self.send("textDocument/didOpen", {"textDocument": {
                "uri": uri, "languageId": language, "version": version, "text": text}})
        else:
            self.send("textDocument/didChange", {"textDocument": {
                "uri": uri, "version": version}, "contentChanges": [{"text": text}]})
        return version

    def diagnostics(self, path, version=None):
        uri = path.as_uri()
        return self.wait(lambda message:
            message.get("method") == "textDocument/publishDiagnostics"
            and message["params"]["uri"] == uri
            and (version is None or message["params"].get("version") == version)
        )["params"]["diagnostics"]

    def query(self, method, path):
        self.next_id += 1
        identifier = self.next_id
        self.send("textDocument/" + method, {"textDocument": {"uri": path.as_uri()},
            "position": {"line": 1, "character": 25}}, identifier)
        return self.wait(lambda message: message.get("id") == identifier)["result"]

    def checkpoints(self):
        log = self.log.read_text()
        assert "idle restart failed" not in log, log
        return log.count("restarting after retained allocation growth")

    def rss(self):
        return int(subprocess.check_output(["ps", "-o", "rss=", "-p", str(self.pid)]))

    def fd_count(self):
        result = subprocess.run(["lsof", "-p", str(self.pid), "-Ff"],
                                capture_output=True, text=True, check=True)
        return sum(line[1:].isdigit() for line in result.stdout.splitlines()
                   if line.startswith("f"))

    def notices(self):
        return [message["params"]["message"] for message in self.messages
                if message.get("method") == "window/showMessage"]

    def close(self):
        self.send("shutdown", identifier=999999)
        self.wait(lambda message: message.get("id") == 999999)
        self.send("exit")
        assert self.process.wait(timeout=20) == 0
        self.stderr.close()


def descendants(pid):
    rows = subprocess.check_output(["ps", "-axo", "pid=,ppid="], text=True)
    pairs = [tuple(map(int, line.split())) for line in rows.splitlines()]
    result = set()
    parents = {pid}
    while parents:
        children = {child for child, parent in pairs if parent in parents}
        result.update(children)
        parents = children
    return result


def probe(root, directory):
    source = directory / "main.x"
    broken = directory / "broken.x"
    orphan = directory / "orphan.x"
    manifest = directory / "x2c.toml"
    header = directory / "live" / "decl.xh"
    (directory / "disk").mkdir()
    header.parent.mkdir()
    (directory / "disk" / "decl.xh").write_text("char value(void);\n")
    header.write_text("int value(void);\n")
    (directory / "helper.x").write_text("meta int twice(int x) => x * 2;\n")
    source.write_text('#include "helper.x"\nint disk_only(void);\n')
    broken.write_text("int disk_ok(void);\n")
    orphan.write_text("int orphan(void);\n")
    manifest.write_text('[target.app]\nsources = ["main.x", "broken.x"]\ninclude-dirs = ["disk"]\n')
    live_manifest = '[target.app]\nsources = ["main.x", "broken.x"]\ninclude-dirs = ["live"]\n'
    source_text = '#include "decl.xh"\nint main(void) { return value() + $twice(1); }\n'
    client = Client(root, directory)
    observed_children = set()
    try:
        client.opened(manifest, live_manifest, "toml")
        client.opened(header, '#include "../helper.x"\ndouble value(void);\n', "c")
        client.opened(source, source_text + "/* snapshot 0: " + "x" * (1024 * 1024) + " */\n")
        diagnostics = client.diagnostics(source)
        assert diagnostics == [], diagnostics
        client.opened(broken, "int broken(;\n")
        assert any(row["code"] == "parse" for row in client.diagnostics(broken))
        client.opened(orphan, orphan.read_text())
        assert client.diagnostics(orphan) == []
        assert "double value(void);" in client.query("hover", source)["contents"]["value"]
        definition = client.query("definition", source)
        assert definition["uri"] == header.as_uri(), definition
        assert len(client.notices()) == 1, client.notices()
        observed_children.update(descendants(client.pid))
        warm_rss = client.rss()
        warm_fds = client.fd_count()
        samples = [{"edit": 0, "checkpoints": 0, "rss_kib": warm_rss}]
        generations = []
        last_generation = 0
        warm_hover = []
        edit_analysis = []
        for _ in range(3):
            start = time.monotonic()
            client.query("hover", source)
            warm_hover.append(time.monotonic() - start)
        for edit in range(1, 201):
            text = source_text + f"/* snapshot {edit}: " + "x" * (1024 * 1024) + " */\n"
            analysis_start = time.monotonic()
            version = client.opened(source, text)
            assert client.diagnostics(source, version) == []
            edit_analysis.append(time.monotonic() - analysis_start)
            # This query also waits for a checkpoint that follows publication.
            start = time.monotonic()
            hover = client.query("hover", source)
            elapsed = time.monotonic() - start
            assert "double value(void);" in hover["contents"]["value"], hover
            generation = client.checkpoints()
            if edit % 10 == 0:
                print(json.dumps({"edit": edit, "checkpoints": generation}), flush=True)
            samples.append({"edit": edit, "checkpoints": generation,
                            "rss_kib": client.rss()})
            if generation > last_generation:
                assert generation == last_generation + 1, generation
                assert client.process.pid == client.pid and client.process.poll() is None
                assert client.query("definition", source) == definition
                client.query("hover", orphan)
                assert len(client.notices()) == 1, client.notices()
                assert client.initialize_responses == 1
                fd_count = client.fd_count()
                assert fd_count <= warm_fds, (warm_fds, fd_count)
                observed_children.update(descendants(client.pid))
                generations.append({"generation": generation, "edit": edit,
                                    "next_hover_seconds": elapsed,
                                    "rss_kib": samples[-1]["rss_kib"], "fds": fd_count})
                print(json.dumps(generations[-1]), flush=True)
                last_generation = generation
                if generation >= 2:
                    break
        assert last_generation >= 2, "workload did not reach two real checkpoints"
        assert client.initialize_responses == 1
        final_rss = client.rss()
        client.close()
        # Every observed helper belongs to this test's server process tree.
        for pid in observed_children:
            result = subprocess.run(["ps", "-p", str(pid), "-o", "pid="], capture_output=True)
            assert not result.stdout.strip(), ("child survives shutdown", pid)
        report = {"pid": client.pid, "warm_rss_kib": warm_rss,
                  "max_sampled_rss_kib": max(row["rss_kib"] for row in samples),
                  "settled_rss_kib": final_rss, "warm_hover_seconds": warm_hover,
                  "first_three_edit_analysis_seconds": edit_analysis[:3],
                  "checkpoints": generations, "samples": samples,
                  "observed_children": sorted(observed_children),
                  "stderr": client.log.read_text()}
        (directory / "report.json").write_text(json.dumps(report, indent=2))
        print(json.dumps({key: value for key, value in report.items()
                          if key not in ("samples", "stderr")}, indent=2))
    finally:
        if client.process.poll() is None:
            client.process.kill()
            client.process.wait()
        client.stderr.close()


if __name__ == "__main__":
    checkout = Path(sys.argv[1]).resolve()
    evidence = Path(tempfile.mkdtemp(prefix="x2c-lsp-restart-")).resolve()
    print(f"evidence: {evidence}", flush=True)
    probe(checkout, evidence)
