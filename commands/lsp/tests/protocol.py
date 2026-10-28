"""Paced source and dependency changes against the resident language server."""
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile


class Client:
    def __init__(self, root, directory, arguments):
        self.process = subprocess.Popen(
            [str(root / "builds/0/libexec/x2c-lsp")], cwd=directory,
            env=dict(os.environ, X2C_CACHE_DIR=str(directory / "cache")),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, bufsize=0)
        self.versions = {}
        self.send("initialize", {"initializationOptions": {"arguments": arguments}}, 1)
        self.wait("id", 1)
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
            message = json.loads(self.process.stdout.read(int(headers["content-length"])))
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
        self.send("textDocument/hover", {"textDocument": {"uri": source.as_uri()},
            "position": {"line": line, "character": character}}, 2)
        return self.wait("id", 2)["result"]

    def close(self):
        self.send("shutdown", identifier=99)
        self.wait("id", 99)
        self.send("exit")
        assert self.process.wait(timeout=10) == 0


root = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="x2c-lsp-protocol-") as temporary:
    directory = Path(temporary).resolve()
    source = directory / "main.x"
    disk = "int value(void);\nint main(void) { return value(); }\n"
    source.write_text(disk)
    client = Client(root, directory, ["translate", str(source)])
    try:
        for separator in ("\n", "\r", "\r\n"):
            line = "int main(void) { /*\U0001f642*/ return value(); }"
            text = "int value(void);" + separator + line + separator
            client.opened(source, text)
            assert client.diagnostics() == []
            column = len(line[:line.index("value")].encode("utf-16-le")) // 2
            hover = client.hover(source, 1, column)
            assert "int value(void);" in hover["contents"]["value"], hover
            assert hover["range"]["start"] == {"line": 1, "character": column}, hover
    finally:
        client.close()

    client = Client(root, directory, ["translate", "--live-symbols", str(source)])
    try:
        client.opened(source, disk)
        assert client.diagnostics() == []
        assert "int value(void);" in client.hover(source, 1, 25)["contents"]["value"]
        client.opened(source, disk + "/* unsaved */\n")
        assert client.diagnostics() == []
        assert client.hover(source, 1, 25) is None
        client.send("textDocument/didSave", {
            "textDocument": {"uri": source.as_uri()}, "text": disk})
        assert client.diagnostics() == []
        assert "int value(void);" in client.hover(source, 1, 25)["contents"]["value"]
    finally:
        client.close()

    client = Client(root, directory, ["translate", str(source)])
    try:
        client.opened(source, disk.replace("int value", "double value"))
        assert client.diagnostics() == []
        assert "double value(void);" in client.hover(source, 1, 25)["contents"]["value"]
        client.send("textDocument/didClose", {"textDocument": {"uri": source.as_uri()}})
        assert client.diagnostics() == []
        assert "int value(void);" in client.hover(source, 1, 25)["contents"]["value"]
    finally:
        client.close()

    header = directory / "decl.xh"
    header.write_text("int value(void);\n")
    source.write_text('#include "decl.xh"\nint main(void) { return value(); }\n')
    client = Client(root, directory, ["translate", str(source)])
    try:
        client.opened(source, source.read_text())
        assert client.diagnostics() == []
        client.opened(header, "double value(void);\n", "c")
        assert client.diagnostics() == []
        assert "double value(void);" in client.hover(source, 1, 25)["contents"]["value"]
        client.send("textDocument/didChange", {"textDocument": {
            "uri": header.as_uri(), "version": 2}, "contentChanges": [
                {"text": "int broken(;\n"}]})
        diagnostics = client.diagnostics()
        assert any(row["code"] == "parse" and row.get("relatedInformation", [{}])[0]
                   .get("location", {}).get("uri") == header.as_uri() for row in diagnostics), diagnostics
    finally:
        client.close()

    source.write_text("int disk_only(void);\n")
    (directory / "helper.x").write_text("meta int twice(int x) => x * 2;\n")
    client = Client(root, directory, ["translate", str(source)])
    try:
        client.opened(source, '#include "helper.x"\n'
            'int value(void) { return $twice(1); }\n')
        assert client.diagnostics() == []
        assert "int value(void);" in client.hover(source, 1, 4)["contents"]["value"]
    finally:
        client.close()
print("language server positions, clean CPP, and dependency overlays passed")
