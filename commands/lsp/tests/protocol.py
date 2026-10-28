"""Paced source and dependency changes against the resident language server."""
from pathlib import Path
import sys
import tempfile

from client import Client


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
        client.opened(source, "int broken(void) { return ; + }\n")
        diagnostics = client.diagnostics()
        assert any(row["code"] == "parse" for row in diagnostics), diagnostics
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
