"""Compiler-backed completion, symbols, navigation, and lexical tokens."""
from pathlib import Path
import sys
import tempfile

from client import Client


def position(text, needle, inside=0):
    at = text.index(needle) + inside
    before = text[:at]
    return {"line": before.count("\n"),
            "character": len(before.rsplit("\n", 1)[-1].encode("utf-16-le")) // 2}


def query(client, method, source, text, needle, inside=0, **extra):
    return client.request("textDocument/" + method, {
        "textDocument": {"uri": source.as_uri()},
        "position": position(text, needle, inside), **extra})


def selected(text, source_range):
    first, last = source_range["start"], source_range["end"]
    assert first["line"] == last["line"], source_range
    line = text.splitlines()[first["line"]].encode("utf-16-le")
    return line[first["character"] * 2:last["character"] * 2].decode("utf-16-le")


def decoded(data):
    line, column = 0, 0
    result = []
    assert len(data) % 5 == 0, data
    for at in range(0, len(data), 5):
        delta_line, delta_column, length, kind, modifiers = data[at:at + 5]
        line += delta_line
        column = delta_column if delta_line else column + delta_column
        assert length > 0 and modifiers == 0
        result.append((line, column, length, kind))
    return result


root = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="x2c-lsp-features-") as temporary:
    directory = Path(temporary).resolve()
    header = directory / "api.xh"
    main = directory / "main.x"
    other = directory / "other.x"
    header_text = "typedef int Count;\nint value(void);\n"
    main_text = ('#include "api.xh"\n'
        'int main(void) { int local_value = 1; /*\U0001f642*/ return value() + local_value; }\n')
    other_text = ('#include "api.xh"\n'
        'int other(void) { return value(); }\n'
        'int shadow(void) { int value = 2; return value; }\n')
    header.write_text(header_text)
    main.write_text(main_text)
    other.write_text(other_text)
    (directory / "x2c.toml").write_text(
        '[target.app]\nsources = ["main.x", "other.x"]\n')
    client = Client(root, directory, [])
    try:
        for source, text in ((main, main_text), (other, other_text)):
            client.opened(source, text)
            assert client.diagnostics() == []

        items = query(client, "completion", main, main_text, "local_value; }", 3)["result"]
        item = next(item for item in items if item["label"] == "local_value")
        assert selected(main_text, item["textEdit"]["range"]) == "local_value", item
        assert all(item["label"].startswith("loc") for item in items), items
        assert query(client, "hover", main, main_text, "value()", 1)["result"]

        symbols = client.request("textDocument/documentSymbol", {
            "textDocument": {"uri": main.as_uri()}})["result"]
        symbol = next(symbol for symbol in symbols if symbol["name"] == "main")
        assert selected(main_text, symbol["selectionRange"]) == "main", symbol
        workspace = client.request("workspace/symbol", {"query": "other"})["result"]
        assert len(workspace) == 1 and workspace[0]["name"] == "other", workspace
        assert workspace[0]["location"]["uri"] == other.as_uri(), workspace

        locations = query(client, "references", main, main_text, "value()", 1,
            context={"includeDeclaration": True})["result"]
        assert len(locations) == 3, locations
        assert {item["uri"] for item in locations} == {
            main.as_uri(), other.as_uri(), header.as_uri()}, locations
        without_declaration = query(client, "references", main, main_text, "value()", 1,
            context={"includeDeclaration": False})["result"]
        assert len(without_declaration) == 2, without_declaration

        edits = query(client, "rename", main, main_text, "value()", 1,
            newName="updated")["result"]["changes"]
        originals = {main.as_uri(): main_text, other.as_uri(): other_text,
                     header.as_uri(): header_text}
        assert sum(map(len, edits.values())) == 3, edits
        for uri, changes in edits.items():
            for edit in changes:
                assert edit["newText"] == "updated"
                assert selected(originals[uri], edit["range"]) == "value", edit
        assert main.read_text() == main_text and other.read_text() == other_text
        assert query(client, "rename", main, main_text, "value()", 1,
            newName="int")["error"]["code"] == -32602

        typed = "typedef int Count;\nCount size(void) { Count count = 1; return count; }\n"
        client.opened(main, typed)
        assert client.diagnostics() == []
        renamed = query(client, "rename", main, typed, "Count", 1,
            newName="Amount")["result"]["changes"]
        assert len(renamed[main.as_uri()]) == 3, renamed
        items = query(client, "completion", main, typed, "Count size", 3)["result"]
        assert any(item["label"] == "Count" for item in items), items

        named = ("class Pair struct { int field; };\n"
                 "int Pair.read(Pair value) { return 1; }\n")
        client.opened(main, named)
        assert client.diagnostics() == []
        symbols = client.request("textDocument/documentSymbol", {
            "textDocument": {"uri": main.as_uri()}})["result"]
        assert {row["name"] for row in symbols} == {"Pair", "Pair.read"}, symbols
        for row in symbols:
            assert selected(named, row["selectionRange"]) == row["name"], row

        member = directory / "member.x"
        member.write_text("typedef int Member;\nint member_function(void) { return 1; }\n")
        module = 'typedef int Main;\nmodule { "member.x", }\n'
        client.opened(main, module)
        assert client.diagnostics() == []
        symbols = client.request("textDocument/documentSymbol", {
            "textDocument": {"uri": main.as_uri()}})["result"]
        assert [row["name"] for row in symbols] == ["Main"], symbols
        workspace = client.request("workspace/symbol", {"query": "member_function"})["result"]
        assert len(workspace) == 1 and workspace[0]["location"]["uri"] == member.as_uri(), workspace

        lexical = "/* a\r\n\U0001f642z */\r\nint value=12; //tail\r"
        client.opened(main, lexical)
        assert client.diagnostics() == []
        tokens = client.request("textDocument/semanticTokens/full", {
            "textDocument": {"uri": main.as_uri()}})["result"]["data"]
        assert decoded(tokens) == [(0, 0, 4, 0), (1, 0, 6, 0),
            (2, 0, 3, 3), (2, 4, 5, 5), (2, 9, 1, 4),
            (2, 10, 2, 2), (2, 12, 1, 4), (2, 14, 6, 0)], decoded(tokens)
        for text, first in (("//tail\r\nint value;\r\n", (0, 0, 6, 0)),
                            ("#define X 1\r\nint value;\r\n", (0, 0, 11, 6))):
            client.opened(main, text)
            assert client.diagnostics() == []
            data = client.request("textDocument/semanticTokens/full", {
                "textDocument": {"uri": main.as_uri()}})["result"]["data"]
            rows = decoded(data)
            assert rows[0] == first and rows[1] == (1, 0, 3, 3), rows
    finally:
        client.close()
print("language server completion, symbols, references, rename, and tokens passed")
