"""Optional regressions retained from the retired one-request editor adapter."""
from pathlib import Path
import sys
import tempfile

from client import Client


def point(text, needle, last=False):
    at = text.rindex(needle) if last else text.index(needle)
    before = text[:at]
    return {"line": before.count("\n"),
            "character": len(before.rsplit("\n", 1)[-1].encode("utf-16-le")) // 2}


def definition(client, source, text, needle, last=False):
    return client.request("textDocument/definition", {
        "textDocument": {"uri": source.as_uri()},
        "position": point(text, needle, last)})["result"]


root = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="x2c-lsp-legacy-") as temporary:
    directory = Path(temporary).resolve()
    source = directory / 'new "quote\\ and space.x'
    text = ("int main(void) {\n  int value = 3;\n"
            "  { int value = 4; value++; }\n  return value;\n}\n")
    client = Client(root, directory, ["translate", str(source)])
    try:
        client.opened(source, text)
        assert client.diagnostics() == []
        assert definition(client, source, text, "value++")["range"]["start"] == {
            "line": 2, "character": 8}
        assert definition(client, source, text, "value", True)["range"]["start"] == {
            "line": 1, "character": 6}
        assert "int value" in client.hover(source, 3, 9)["contents"]["value"]
    finally:
        client.close()

    source = directory / "main.x"
    kept, helper = directory / "kept.x", directory / "keep.x"
    macro = "macro Unit $keep(Decl $target) { using $private; $target }\n"
    included = '#include "keep.x"\n$keep(int supplied);\n'
    text = '#include "kept.x"\nint main(void) { return supplied; }\n'
    client = Client(root, directory, ["translate", str(source)])
    try:
        client.opened(helper, macro, "c")
        client.opened(kept, included, "c")
        client.opened(source, text)
        assert client.diagnostics() == []
        found = definition(client, source, text, "supplied")
        assert found["uri"] == kept.as_uri(), found
        assert found["range"]["start"] == point(included, "supplied"), found
        same_file = macro + "$keep(int supplied);\n"
        client.opened(kept, same_file, "c")
        assert client.diagnostics() == []
        found = definition(client, source, text, "supplied")
        assert found["range"]["start"] == point(same_file, "supplied"), found
        client.opened(kept, "\n\n" + same_file, "c")
        assert client.diagnostics() == []
        found = definition(client, source, text, "supplied")
        assert found["range"]["start"]["line"] == 3, found
        assert not kept.exists(), "unsaved include was written to disk"
        dropped = ('macro Unit $drop(Decl $target) {}\n$drop(int erased);\n'
                   'int erased;\nint main(void) { return erased; }\n')
        client.opened(source, dropped)
        assert client.diagnostics() == []
        assert definition(client, source, dropped, "erased") is None
        client.opened(source, "int main(void) {")
        assert client.diagnostics()
        client.opened(source, "int main(void) { return 0; }\n")
        assert client.diagnostics() == []
    finally:
        client.close()

    packages = directory / "packages"
    entry = packages / "toy" / "toy.x"
    entry.parent.mkdir(parents=True)
    entry.write_text("int answer(void);\n")
    (directory / "x2c.toml").write_text(
        '[target.app]\nsources=["main.x"]\npackage-dirs=["packages"]\n')
    text = 'import "toy" as t;\nint main(void) { return t.answer(); }\n'
    source.write_text(text)
    client = Client(root, directory, [])
    try:
        client.opened(entry, "\nint answer(void);\n", "c")
        client.opened(source, text)
        assert client.diagnostics() == []
        found = definition(client, source, text, "answer")
        assert found["uri"] == entry.as_uri(), found
        assert found["range"]["start"] == {"line": 1, "character": 4}, found
    finally:
        client.close()

    macro_file = directory / "helper.x"
    macro = "macro Expression $twice($value) => $value + $value;\n"
    macro_file.write_text(macro)
    text = '#include "helper.x"\nint main(void) { return $twice(2); }\n'
    source.write_text(text)
    client = Client(root, directory, ["translate", str(source)])
    try:
        client.opened(source, text)
        assert client.diagnostics() == []
        client.opened(macro_file, "macro Expression $twice($value) => (", "c")
        assert client.diagnostics()
        client.opened(macro_file, macro, "c")
        assert client.diagnostics() == []
        assert macro_file.read_text() == macro
    finally:
        client.close()

    header = directory / "input.h"
    header.write_text("int answer;\n")
    text = '#include "input.h"\nint main(void) { return answer; }\n'
    source.write_text(text)
    client = Client(root, directory, ["translate", "--live-symbols", str(source)])
    try:
        client.opened(source, text)
        assert client.diagnostics() == []
        client.opened(directory / "unrelated.x", "int unrelated;", "c")
        assert "int answer" in client.hover(source, 1, 25)["contents"]["value"]
        client.opened(header, "\nint answer;\n", "c")
        assert client.diagnostics() == []
        assert client.hover(source, 1, 25) is None
        assert header.read_text() == "int answer;\n"
    finally:
        client.close()
print("retired editor overlay, binding, macro, package, and native CPP regressions passed")
