"""Framed client shared by the language server protocol tests."""
import json
import os
import select
import subprocess


class Client:
    def __init__(self, root, directory, arguments, compiler=None):
        self.process = subprocess.Popen(
            ([str(compiler), "lsp"] if compiler else
             [str(root / "builds/0/libexec/x2c-lsp")]), cwd=directory,
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

    def frame(self, method, params=None, identifier=None):
        message = {"jsonrpc": "2.0", "method": method, "params": params or {}}
        if identifier is not None:
            message["id"] = identifier
        body = json.dumps(message).encode()
        return f"Content-Length: {len(body)}\r\n\r\n".encode() + body

    def send(self, method, params=None, identifier=None):
        data = self.frame(method, params, identifier)
        while data:
            count = self.process.stdin.write(data)
            assert count, "server stdin closed"
            data = data[count:]
        self.process.stdin.flush()

    # The gate runs the command checks beside parallel compiles, so a
    # response may take tens of seconds; a hang still fails within a minute.
    TIMEOUT = 60

    def read(self, count):
        chunks = []
        while count:
            assert select.select([self.process.stdout], [], [],
                                 self.TIMEOUT)[0], "response timeout"
            chunk = os.read(self.process.stdout.fileno(), count)
            assert chunk, ("server ended", self.process.poll())
            chunks.append(chunk)
            count -= len(chunk)
        return b"".join(chunks)

    def message(self):
        header = bytearray()
        while not header.endswith(b"\r\n\r\n"):
            header.extend(self.read(1))
        fields = dict(line.lower().split(":", 1)
                      for line in header.decode().strip().split("\r\n"))
        return json.loads(self.read(int(fields["content-length"])))

    def wait_for(self, predicate):
        while True:
            message = self.message()
            if predicate(message):
                return message

    def wait(self, key, value):
        return self.wait_for(lambda message: message.get(key) == value)

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
        return version

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

    def close(self, identifier=99, timeout=10):
        self.send("shutdown", identifier=identifier)
        self.wait_for(lambda message: message.get("id") == identifier)
        self.send("exit")
        assert self.process.wait(timeout=timeout) == 0


def position(text, needle, inside=0, last=False):
    at = (text.rindex(needle) if last else text.index(needle)) + inside
    before = text[:at]
    return {"line": before.count("\n"),
            "character": len(before.rsplit("\n", 1)[-1].encode("utf-16-le")) // 2}
