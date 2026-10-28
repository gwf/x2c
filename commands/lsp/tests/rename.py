"""Apply binding-aware workspace edits, then compile and run the result."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlparse

from client import Client


def position(text, needle):
    before = text[:text.index(needle) + 1]
    return {"line": before.count("\n"),
            "character": len(before.rsplit("\n", 1)[-1].encode("utf-16-le")) // 2}


def offset(text, point):
    lines = text.splitlines(keepends=True)
    before = "".join(lines[:point["line"]])
    line = lines[point["line"]].encode("utf-16-le")
    return len(before) + len(line[:point["character"] * 2].decode("utf-16-le"))


def apply(texts, changes):
    result = dict(texts)
    for uri, edits in changes.items():
        name = Path(unquote(urlparse(uri).path)).name
        original = texts[name]
        text = original
        last = len(original)
        for edit in sorted(edits, key=lambda edit:
                           offset(original, edit["range"]["start"]), reverse=True):
            first = offset(original, edit["range"]["start"])
            after = offset(original, edit["range"]["end"])
            assert first < after <= last, edits
            text = text[:first] + edit["newText"] + text[after:]
            last = first
        result[name] = text
    return result


def build(root, directory, texts, inputs):
    directory.mkdir()
    for name, text in texts.items():
        (directory / name).write_text(text)
    executable = directory / "app"
    compiled = subprocess.run([
        str(root / "builds/0/x2c"), "build", "--plain", "--output", str(executable),
        "--build-dir", str(directory / "build"), "-I", str(directory),
        *(str(directory / name) for name in inputs)], cwd=directory,
        env=dict(os.environ, X2C_CACHE_DIR=str(directory / "cache")),
        capture_output=True, text=True, timeout=60)
    assert compiled.returncode == 0, compiled.stdout + compiled.stderr
    ran = subprocess.run([str(executable)], capture_output=True, timeout=5)
    assert ran.returncode == 0, (ran.returncode, ran.stdout, ran.stderr)


def check_case(root, directory, texts, inputs, selections, manifest=True):
    directory.mkdir()
    for name, text in texts.items():
        (directory / name).write_text(text)
    if manifest:
        sources = ", ".join('"' + name + '"' for name in inputs)
        (directory / "x2c.toml").write_text('[target.app]\nsources = [' + sources + ']\n')
    build(root, directory / "baseline", texts, inputs)
    arguments = [] if manifest else ["translate", str(directory / inputs[0])]
    client = Client(root, directory, arguments)
    try:
        for name in inputs:
            client.opened(directory / name, texts[name])
            assert client.diagnostics() == []
        for index, (name, needle, new_name, count) in enumerate(selections):
            response = client.request("textDocument/rename", {
                "textDocument": {"uri": (directory / name).as_uri()},
                "position": position(texts[name], needle), "newName": new_name})
            assert "result" in response, response
            changes = response["result"]["changes"]
            assert sum(map(len, changes.values())) == count, changes
            changed = apply(texts, changes)
            build(root, directory / ("renamed-" + str(index)), changed, inputs)
            assert all((directory / name).read_text() == text
                       for name, text in texts.items())
    finally:
        client.close()


root = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="x2c-lsp-rename-") as temporary:
    work = Path(temporary).resolve()
    check_case(root, work / "linkage", {
        "api.xh": "int shared(int value);\n",
        "a.x": ('#include "api.xh"\n'
                'int shared(int value) { return value + 1; }\n'
                'static int private_value(void) { return 2; }\n'
                'int a_local(void) { int shared = 3; return shared + private_value(); }\n'
                'int impl_call(void) { return shared(4); }\n'),
        "b.x": ('#include "api.xh"\n'
                'static int private_value(void) { return 5; }\n'
                'int main(void) { return shared(1) == 2 && private_value() == 5 ? 0 : 1; }\n')},
        ["a.x", "b.x"], [
            ("a.x", "shared(int", "updated", 4),
            ("b.x", "shared(1", "updated", 4),
            ("a.x", "private_value(void", "private_new", 2),
            ("a.x", "shared = 3", "local_new", 2)])
    check_case(root, work / "objects", {
        "api.xh": "extern int shared_count;\nint bump(void);\n",
        "a.x": ('#include "api.xh"\nint shared_count = 2;\n'
                'int bump(void) { return ++shared_count; }\n'),
        "b.x": ('#include "api.xh"\n'
                'int main(void) { return bump() == 3 && shared_count == 3 ? 0 : 1; }\n')},
        ["a.x", "b.x"], [
            ("a.x", "shared_count =", "updated_count", 4),
            ("b.x", "shared_count ==", "updated_count", 4)])
    check_case(root, work / "methods", {"main.x": (
        'typedef int Counter;\n'
        'int Counter.peek(Counter value) { return value; }\n'
        'int main(void) { Counter c = 1; '
        'return c.peek() + Counter.peek(c) + Counter_peek(c) == 3 ? 0 : 1; }\n')},
        ["main.x"], [
            ("main.x", "Counter;", "Amount", 6),
            ("main.x", "peek(Counter", "look", 4)], manifest=False)
    check_case(root, work / "recursive", {"main.x": (
        'class Pair struct { Pair *next; int value; } *;\n'
        'int main(void) { struct Pair storage = {NULL, 1}; Pair pair = &storage; '
        'return pair->value == 1 ? 0 : 1; }\n')}, ["main.x"],
        [("main.x", "Pair struct", "Node", 4)], manifest=False)
print("language server applied rename edits compile and run")
