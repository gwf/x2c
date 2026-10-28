"""Framed client shared by the language server protocol tests."""
import json
import os
import select
import subprocess


class Client:
    def __init__(self, root, directory, arguments):
        self.process = subprocess.Popen(
            [str(root / "builds/0/libexec/x2c-lsp")], cwd=directory,
            env=dict(os.environ, X2C_CACHE_DIR=str(directory / "cache")),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, bufsize=0)
        self.versions = {}
        self.next_id = 10
        self.send("initialize", {
            "capabilities": {"workspace": {"applyEdit": True},
                "textDocument": {"hover": {"dynamicRegistration": False}}},
            "initializationOptions": {"arguments": arguments}}, 1)
        initialized = self.wait("id", 1)
        assert "result" in initialized, initialized
        self.capabilities = initialized["result"]["capabilities"]
        self.send("initialized")

    def send(self, method, params=None, identifier=None):
        message = {"jsonrpc": "2.0", "method": method, "params": params or {}}
        if identifier is not None:
            message["id"] = identifier
        body = json.dumps(message).encode()
        self.process.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
        self.process.stdin.flush()

    def wait(self, key, value):
        while True:
            assert select.select([self.process.stdout], [], [], 20)[0], "response timeout"
            headers = {}
            while (line := self.process.stdout.readline()) not in (b"\n", b"\r\n"):
                assert line, (self.process.poll(), self.process.stderr.read())
                name, field = line.decode().split(":", 1)
                headers[name.lower()] = field.strip()
            remaining = int(headers["content-length"])
            chunks = []
            while remaining:
                assert select.select([self.process.stdout], [], [], 20)[0], "body timeout"
                chunk = self.process.stdout.read(remaining)
                assert chunk, "server closed an incomplete frame"
                chunks.append(chunk)
                remaining -= len(chunk)
            message = json.loads(b"".join(chunks))
            if message.get(key) == value:
                return message

    def opened(self, source, text, language="x2c"):
        uri = source.as_uri()
        version = self.versions.get(uri, 0) + 1
        self.versions[uri] = version
        if version == 1:
            self.send("textDocument/didOpen", {"textDocument": {
                "uri": uri, "languageId": language, "version": version, "text": text}})
        else:
            self.send("textDocument/didChange", {"textDocument": {
                "uri": uri, "version": version}, "contentChanges": [{"text": text}]})

    def diagnostics(self):
        return self.wait("method", "textDocument/publishDiagnostics")["params"]["diagnostics"]

    def hover(self, source, line, character):
        return self.request("textDocument/hover", {
            "textDocument": {"uri": source.as_uri()},
            "position": {"line": line, "character": character}})["result"]

    def request(self, method, params):
        self.next_id += 1
        self.send(method, params, self.next_id)
        return self.wait("id", self.next_id)

    def close(self):
        self.send("shutdown", identifier=99)
        self.wait("id", 99)
        self.send("exit")
        assert self.process.wait(timeout=10) == 0

