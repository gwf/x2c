"""Compiler-backed completion, symbols, and navigation."""
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
        # Leave coloring to the editor's richer syntax grammar.
        assert "semanticTokensProvider" not in client.capabilities, client.capabilities
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

        prototypes = ("int repeated(void);\n"
                      "int repeated(void) { return 1; }\n"
                      "int use_repeated(void) { return repeated(); }\n")
        client.opened(main, prototypes)
        assert client.diagnostics() == []
        for include, count in ((False, 1), (True, 3)):
            references = query(client, "references", main, prototypes,
                               "repeated(); }", 1,
                               context={"includeDeclaration": include})["result"]
            assert len(references) == count, references

        named = ("class Pair struct { int field; };\n"
                 "int Pair.read(Pair value) { return 1; }\n")
        client.opened(main, named)
        assert client.diagnostics() == []
        symbols = client.request("textDocument/documentSymbol", {
            "textDocument": {"uri": main.as_uri()}})["result"]
        assert {row["name"] for row in symbols} == {"Pair", "Pair.read"}, symbols
        for row in symbols:
            assert selected(named, row["selectionRange"]) == row["name"], row

        members = ("typedef struct CompletionProbe { int field_value; int other; } CompletionProbe;\n"
                   "int read_members(CompletionProbe value,CompletionProbe *pointer) { "
                   "/*\U0001f642*/ return value.field_value + pointer->field_value; }\n")
        client.opened(main, members)
        assert client.diagnostics() == []
        for needle, inside in (("value.field_value", len("value.fi")),
                               ("pointer->field_value", len("pointer->fi"))):
            items = query(client, "completion", main, members, needle, inside)["result"]
            assert [item["label"] for item in items] == ["field_value"], items
            item = items[0]
            assert item["kind"] == 5 and item["textEdit"]["newText"] == "field_value", item
            assert selected(members, item["textEdit"]["range"]) == "field_value", item

        # Source positions remain physical UTF-16 positions across CRLF and
        # supplementary characters, including declarations with shadowed names.
        positioned = ("/*\U0001f642*/ typedef int Item;\r\n"
                      "/*\U0001f642*/ int first(void) { int first = 1; return first; }\r\n"
                      "int second(void) { int first = 2; return first; }\r\n")
        client.opened(main, positioned)
        assert client.diagnostics() == []
        symbols = client.request("textDocument/documentSymbol", {
            "textDocument": {"uri": main.as_uri()}})["result"]
        assert [row["name"] for row in symbols] == ["Item", "first", "second"], symbols
        for row in symbols:
            assert selected(positioned, row["selectionRange"]) == row["name"], row
        assert symbols[0]["selectionRange"]["start"] == position(positioned, "Item"), symbols
        assert symbols[1]["selectionRange"]["start"] == position(positioned, "first"), symbols

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

    finally:
        client.close()
with tempfile.TemporaryDirectory(prefix="x2c-lsp-dependencies-") as temporary:
    directory = Path(temporary).resolve()
    library, main = directory / "lib.x", directory / "main.x"
    library_text = ('#pragma once\nint value(void) { return 1; }\n'
                    'int helper(void) { return value(); }\n')
    main_text = '#include "lib.x"\nint main(void) { return value(); }\n'
    library.write_text(library_text)
    main.write_text(main_text)
    (directory / "x2c.toml").write_text(
        '[project]\ndefault-target = "app"\n'
        '[target.dep]\nkind = "static-library"\nsources = ["lib.x"]\n'
        '[target.app]\nsources = ["main.x"]\ndependencies = ["dep"]\n')
    client = Client(root, directory, [])
    try:
        client.opened(main, main_text)
        assert client.diagnostics() == []
        references = query(client, "references", main, main_text, "value()", 1,
                           context={"includeDeclaration": True})["result"]
        assert len(references) == 3, references
        assert sum(row["uri"] == library.as_uri() for row in references) == 2, references
    finally:
        client.close()
with tempfile.TemporaryDirectory(prefix="x2c-lsp-type-scope-") as temporary:
    directory = Path(temporary).resolve()
    header, main = directory / "api.xh", directory / "main.x"
    header_text = ('typedef int Counter;\n'
                   'Counter helper(Counter value) { return value; }\n')
    main_text = ('#include "api.xh"\n'
                 'int main(void) { Counter value = 1; return helper(value) == 1 ? 0 : 1; }\n')
    header.write_text(header_text)
    main.write_text(main_text)
    client = Client(root, directory, ["translate", str(main)])
    try:
        client.opened(main, main_text)
        assert client.diagnostics() == []
        response = query(client, "rename", main, main_text, "Counter", 1,
                         newName="Amount")
        assert response["error"]["code"] == -32803, response
        assert "selected source units" in response["error"]["message"], response
        assert "result" not in response and "changes" not in response, response
        assert header.read_text() == header_text and main.read_text() == main_text
        references = query(client, "references", main, main_text, "Counter", 1,
                           context={"includeDeclaration": True})["result"]
        assert len(references) == 2, references
    finally:
        client.close()
with tempfile.TemporaryDirectory(prefix="x2c-lsp-script-") as temporary:
    directory = Path(temporary).resolve()
    script = directory / "tool.x"
    script_text = "#!/usr/bin/env x2c\nint answer(void) { return 42; }\n"
    script.write_text(script_text)
    client = Client(root, directory, ["translate", str(script)])
    client.opened(script, script_text)
    assert client.diagnostics() == []
    # A save without text keeps the script's own first line as the overlay;
    # compiler ranges still convert through the text the compiler read.
    hover = query(client, "hover", script, script_text, "answer")["result"]
    assert selected(script_text, hover["range"]) == "answer", hover
    client.send("textDocument/didSave",
                {"textDocument": {"uri": script.as_uri()}})
    assert client.diagnostics() == []
    hover = query(client, "hover", script, script_text, "answer")["result"]
    assert selected(script_text, hover["range"]) == "answer", hover
    # One write queues the change before exit, so no idle point publishes it.
    client.process.stdin.write(client.frame("textDocument/didChange", {
        "textDocument": {"uri": script.as_uri(), "version": 2},
        "contentChanges": [{"text": "int value(\n"}]}) + client.frame("exit"))
    client.process.stdin.close()
    remaining = client.process.stdout.read()
    assert client.process.wait(timeout=20) == 1
    assert b"publishDiagnostics" not in remaining, remaining
print("language server completion, symbols, references, rename, scripts, "
      "and exit passed")
