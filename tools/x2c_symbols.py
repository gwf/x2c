#!/usr/bin/env python3
"""Read the compiler's own header-symbol artifact.

`etc/header-symbols.xlisp` is written by `src/collect.x:header_symbols_write`
and byte-compared by `make hdr-check`. It records, per source file, a
content hash and every symbol with a canonical Type list. That makes it the
authoritative source of signatures for documentation: nothing here re-derives a
type from source.

Two pieces of knowledge are duplicated from the runtime and are deliberately
narrow. `content_hash` mirrors `String.hash` (`lib/string.x`), and
`read_sexp` mirrors the subset of the Lisp grammar that
`snapshot_write_var` (`src/snapshot.x:16`) emits. Both are pinned: a grammar
change moves the artifact's version integer, and a hash change makes every file
comparison fail at once. Neither can drift quietly into a plausible wrong
answer, which is the only kind of drift that would matter here.

Run `python3 tools/x2c_symbols.py --selftest` to check both against the tree.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
ARTIFACT = ROOT / "etc" / "header-symbols.xlisp"
SNAPSHOT = ROOT / "etc" / "symbols.xlisp"
ARTIFACT_VERSION = 10
UINT32 = 0xFFFFFFFF
UINT64 = 0xFFFFFFFFFFFFFFFF
# String.escape emits these and nothing else; anything outside [32,126] becomes
# a three-digit octal escape (lib/string.x:948-998).
ESCAPES = {"n": "\n", "r": "\r", "t": "\t", "b": "\b", "f": "\f",
           "v": "\v", "\\": "\\", '"': '"', "'": "'"}


class Symbol(str):
    """A bare s-expression token, distinct from a quoted string."""

    __slots__ = ()


BASE_SPECIFIERS = frozenset({
    "void", "char", "short", "int", "long", "unsigned", "signed", "float",
    "double", "const", "volatile",
})


def content_hash(data: bytes) -> str:
    """The word mixer of `_hash_n` (`lib/string.x`).

    Runtime words use little-endian byte order so this mirror and the tracked
    artifacts stay identical on every host.
    """
    def mix64(word: int) -> int:
        word ^= word >> 33
        word = (word * 0xFF51AFD7ED558CCD) & UINT64
        word ^= word >> 33
        word = (word * 0xC4CEB9FE1A85EC53) & UINT64
        word ^= word >> 33
        return word

    mixed = mix64(len(data))
    for offset in range(0, len(data), 8):
        word = int.from_bytes(data[offset:offset + 8], "little")
        mixed = mix64(mixed ^ word)
    value = mix64(mixed) & UINT32
    return f"{value if value else UINT32:08x}"


def _read_string(text: str, index: int) -> tuple[str, int]:
    out: list[str] = []
    while index < len(text):
        char = text[index]
        if char == '"':
            return "".join(out), index + 1
        if char != "\\":
            out.append(char)
            index += 1
            continue
        nxt = text[index + 1]
        if nxt in ESCAPES:
            out.append(ESCAPES[nxt])
            index += 2
            continue
        if nxt.isdigit():
            octal = text[index + 1:index + 4]
            if len(octal) != 3 or not all(c in "01234567" for c in octal):
                raise ValueError(f"bad octal escape at offset {index}")
            out.append(chr(int(octal, 8)))
            index += 4
            continue
        raise ValueError(f"unsupported escape \\{nxt} at offset {index}")
    raise ValueError("unterminated string")


def read_sexp(text: str) -> list:
    """Parse the subset of Lisp that the snapshot writer emits."""
    stack: list[list] = []
    result: list = []
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        if char.isspace():
            index += 1
            continue
        if char == "(":
            node: list = []
            stack.append(node)
            index += 1
            continue
        if char == ")":
            if not stack:
                raise ValueError(f"unbalanced ')' at offset {index}")
            node = stack.pop()
            (stack[-1] if stack else result).append(node)
            index += 1
            continue
        if char == '"':
            value, index = _read_string(text, index + 1)
            (stack[-1] if stack else result).append(value)
            continue
        if char in "'`,#@[]{}":
            raise ValueError(f"unexpected {char!r} at offset {index}")
        end = index
        while end < length and not text[end].isspace() and text[end] not in "()":
            end += 1
        token = text[index:end]
        if re.fullmatch(r"-?\d+", token):
            value = int(token)
        elif re.fullmatch(r"-?\d+\.\d*(?:[eE][-+]?\d+)?", token):
            value = float(token)
        else:
            value = Symbol(token)
        (stack[-1] if stack else result).append(value)
        index = end
    if stack:
        raise ValueError("unterminated list")
    return result


def render_abstract(node) -> str:
    """Render a canonical Type list as an abstract declarator.

    Only needs to be canonical enough to compare against source text, but it
    must be a correct declarator: `Var (*)(Var)` and `Var *(Var)` differ.
    Unknown nodes raise rather than guess.
    """
    return _render(node, "")


def _base(node) -> tuple[list, str]:
    """Split a type list into (remaining head, base spelling)."""
    if isinstance(node, str):
        return [], str(node)
    raise ValueError(f"not a base type: {node!r}")


def _render(node, decl: str) -> str:
    if isinstance(node, str):
        return f"{node} {decl}".strip()
    if not isinstance(node, list):
        raise ValueError(f"unrenderable type node: {node!r}")
    if not node:
        raise ValueError("empty type node")
    if len(node) == 1:
        return _render(node[0], decl)
    if all(isinstance(part, Symbol) and part in BASE_SPECIFIERS
           for part in node):
        # A multi-word base type such as (long double) or (unsigned long).
        return f"{' '.join(node)} {decl}".strip()
    head = node[0]
    rest = node[1:]
    if isinstance(head, Symbol) and head == "*":
        inner = f"*{decl}"
        target = rest if len(rest) > 1 else rest[0]
        if _needs_parens(target):
            inner = f"({inner})"
        return _render(target, inner)
    if isinstance(head, Symbol) and head in ("const", "volatile"):
        target = rest if len(rest) > 1 else rest[0]
        return f"{head} {_render(target, decl)}".strip()
    if isinstance(head, Symbol) and head in ("struct", "union", "enum"):
        if len(rest) != 1:
            raise ValueError(f"unexpected {head} node: {node!r}")
        return f"{head} {rest[0]} {decl}".strip()
    if isinstance(head, list) and head and isinstance(head[0], Symbol) \
            and head[0] == "func":
        params = _params(head[1] if len(head) > 1 else [])
        target = rest if len(rest) > 1 else rest[0]
        return _render(target, f"{decl}({params})")
    if isinstance(head, list) and head and isinstance(head[0], Symbol) \
            and head[0] == "dim":
        extent = head[1][0] if len(head) > 1 and head[1] else ""
        target = rest if len(rest) > 1 else rest[0]
        return _render(target, f"{decl}[{extent}]")
    raise ValueError(f"unknown type node: {node!r}")


def _needs_parens(target) -> bool:
    if isinstance(target, list) and target and isinstance(target[0], list):
        inner = target[0]
        return bool(inner) and isinstance(inner[0], Symbol) and \
            inner[0] in ("func", "dim")
    return False


def _params(node) -> str:
    if not isinstance(node, list):
        raise ValueError(f"bad parameter list: {node!r}")
    rendered = []
    for entry in node:
        if isinstance(entry, list) and len(entry) == 1 and \
                isinstance(entry[0], Symbol) and entry[0] == "void":
            return "void"
        if isinstance(entry, Symbol) and entry == "void":
            return "void"
        if isinstance(entry, list) and len(entry) == 1 and \
                isinstance(entry[0], Symbol) and entry[0] == "...":
            rendered.append("...")
            continue
        rendered.append(render_abstract(entry))
    return ", ".join(rendered)


class FuncType:
    """A function's return and parameter types, as the compiler recorded them."""

    __slots__ = ("returns", "params")

    def __init__(self, returns: str, params: tuple[str, ...]) -> None:
        self.returns = returns
        self.params = params

    def __repr__(self) -> str:
        return f"FuncType({self.returns!r}, {self.params!r})"


class HeaderSymbols:
    """The parsed artifact, indexed by source path."""

    def __init__(self, tree: list) -> None:
        if len(tree) != 1 or not isinstance(tree[0], list):
            raise ValueError("artifact is not a single s-expression")
        node = tree[0]
        if not node or node[0] != "header-symbols":
            raise ValueError("artifact is not a header-symbols form")
        self.version = node[1]
        if self.version != ARTIFACT_VERSION:
            raise ValueError(
                f"artifact version {self.version}, expected {ARTIFACT_VERSION}"
                "; src/collect.x:header_symbols_write changed shape"
            )
        self.gensym_base = node[2]
        self.snapshot_hash = node[3]
        self._entries: dict[str, list] = {}
        for entry in node[4]:
            self._entries[str(entry[0])] = entry
        self._cache: dict[str, dict[str, object]] = {}

    def paths(self) -> tuple[str, ...]:
        return tuple(sorted(self._entries))

    def file_hash(self, path: str) -> str:
        return str(self._entries[path][1])

    def rows(self, path: str) -> dict[str, object]:
        """Every symbol in the entry, unioning all rows tables.

        An entry's parts are dependency paths interleaved with one rows table
        per `#pragma private` segment. Taking only the last table silently
        loses 61 `lib/common.x` functions, so the union is the correct rule.
        """
        if path in self._cache:
            return self._cache[path]
        table: dict[str, object] = {}
        for part in self._entries[path][3]:
            if not isinstance(part, list):
                continue
            for row in part:
                if not (isinstance(row, list) and len(row) == 2):
                    continue
                name, value = row
                if isinstance(name, list) and len(name) == 1 and \
                        isinstance(name[0], str) and not isinstance(
                            name[0], Symbol):
                    table[str(name[0])] = value
        self._cache[path] = table
        return table

    def declaration_functions(self, path: str) -> tuple[str, ...]:
        """Selected callable recipes retained by declaration projection.

        Follow only declaration ownership rows. Function bodies and captured
        macro environments are unrelated syntax, even if they contain a
        matching-looking List.
        """
        names: list[str] = []

        def visit(node):
            if not isinstance(node, list) or not node:
                return
            if node[0] == "declaration-source":
                visit(node[2])
            elif node[0] == "declaration-origin":
                visit(node[2])
            elif node[0] in ("declaration-bundle", "rows", "seq"):
                for child in node[1:]:
                    visit(child)
            elif node[0] == "declaration-function":
                declaration = node[1]
                binding = declaration[2][1][1]
                if isinstance(binding, list) and binding[0] == "binding":
                    names.append(str(binding[2]))
                elif isinstance(binding, list) and len(binding) == 1:
                    names.append(str(binding[0]))

        for part in self._entries[path][3]:
            if not isinstance(part, list):
                continue
            for row in part:
                if isinstance(row, list) and len(row) == 2:
                    key, value = row
                    if isinstance(key, list) and key and key[0] == "source-node":
                        visit(value)
        return tuple(dict.fromkeys(names))

    def functions(self, path: str) -> dict[str, FuncType]:
        """Only the func-typed rows, rendered for comparison."""
        out: dict[str, FuncType] = {}
        for name, value in self.rows(path).items():
            if not (isinstance(value, list) and len(value) >= 2):
                continue
            head = value[0]
            if not (isinstance(head, list) and head and
                    isinstance(head[0], Symbol) and head[0] == "func"):
                continue
            params = head[1] if len(head) > 1 else []
            rendered: list[str] = []
            for entry in params:
                if isinstance(entry, list) and len(entry) == 1 and \
                        isinstance(entry[0], Symbol) and entry[0] == "void":
                    continue
                rendered.append(render_abstract(entry))
            # A pointer return spreads over the remaining elements, e.g.
            # Scope_malloc is (func ((size_t))) * void -> "void *".
            tail = value[1:] if len(value) > 2 else value[1]
            out[name] = FuncType(render_abstract(tail), tuple(rendered))
        return out


def definitions_with_symbols(path: pathlib.Path, symbols: HeaderSymbols,
                             include_static: bool = False, root=ROOT):
    """Join authored documentation to compiler-selected declaration output."""
    from x2c_source import (
        Definition, definitions_for_path, public_declarations_for_path,
    )

    authored = list(definitions_for_path(path, include_static))
    classes = [item for item in public_declarations_for_path(path)
               if item.kind == "class"]
    if not classes:
        return tuple(authored)
    relative = path.resolve().relative_to(root).as_posix()
    if relative not in symbols.paths():
        return tuple(authored)
    known = {item.name.replace(".", "_") for item in authored}
    table = symbols.functions(relative)
    for native in symbols.declaration_functions(relative):
        if native in known or native not in table:
            continue
        owner = next((item for item in sorted(classes,
                     key=lambda item: -len(item.name))
                     if native.startswith(item.name + "_")), None)
        if owner is None:
            owner = next((item for item in classes
                          if native == "Var_" + item.name.lower()), None)
            if owner is None:
                continue
            name = "Var." + owner.name.lower()
        else:
            name = owner.name + "." + native[len(owner.name) + 1:]
        entry = table[native]
        parameters = ", ".join(entry.params) or "void"
        doc = (f"Provides the class default for `{name}`.\n\n"
               "See [Classes and system macros]"
               "(../../guide/system-macros.md) for the default behavior.")
        authored.append(Definition(name,
            f"{entry.returns} {name}({parameters})", owner.line, doc))
        known.add(native)
    authored.sort(key=lambda item: item.line)
    return tuple(authored)


def load(path: pathlib.Path = ARTIFACT) -> HeaderSymbols:
    return HeaderSymbols(read_sexp(path.read_text(encoding="utf-8")))


SPECIFIER_ORDER = ("const", "volatile", "unsigned", "signed", "long", "short",
                   "char", "int", "float", "double", "void", "size_t")


def normalize_type(text: str) -> str:
    """Canonicalize a type spelling so source and artifact can be compared."""
    text = re.sub(r"\s+", " ", text).strip()
    text = re.sub(r"\s*\*\s*", " * ", text)
    text = re.sub(r"\s+", " ", text).strip()
    parts = text.split(" ")
    stars = [p for p in parts if p == "*"]
    words = [p for p in parts if p != "*"]
    if "int" in words and any(
        w in words for w in ("long", "short", "unsigned", "signed")
    ):
        words = [w for w in words if w != "int"]
    if "signed" in words and "char" not in words:
        words = [w for w in words if w != "signed"]
    words.sort(key=lambda w: (SPECIFIER_ORDER.index(w)
                              if w in SPECIFIER_ORDER else -1, w))
    return " ".join(words + stars)


def selftest() -> int:
    """Reproduce the artifact's hashes and cross-check every signature."""
    sys.path.insert(0, str(ROOT / "tools"))
    from x2c_source import definitions_for_path, split_signature

    symbols = load()
    failures: list[str] = []

    snapshot = content_hash(SNAPSHOT.read_bytes())
    ok_snapshot = snapshot == symbols.snapshot_hash
    if not ok_snapshot:
        failures.append(
            f"snapshot hash {snapshot} != artifact {symbols.snapshot_hash}"
        )

    matched = 0
    for path in symbols.paths():
        source = ROOT / path
        if not source.exists():
            failures.append(f"{path}: artifact names a missing source")
            continue
        actual = content_hash(source.read_bytes())
        if actual == symbols.file_hash(path):
            matched += 1
        else:
            failures.append(
                f"{path}: content hash {actual} != artifact "
                f"{symbols.file_hash(path)}; run 'make hdr-sync'"
            )

    checked = 0
    for path in symbols.paths():
        if not path.startswith("lib/"):
            continue
        table = symbols.functions(path)
        for definition in definitions_for_path(ROOT / path):
            if "." not in definition.name:
                continue
            if definition.signature.startswith("static "):
                continue
            c_name = definition.name.replace(".", "_")
            entry = table.get(c_name)
            if entry is None:
                failures.append(f"{path}:{definition.line}: {definition.name} "
                                "is absent from the artifact")
                continue
            ret, _, params = split_signature(definition.signature)
            owner = definition.name.split(".", 1)[0]
            ret = re.sub(r"\bSelf\b", owner, ret)
            params = tuple(
                re.sub(r"\bSelf\b", owner, param) for param in params
            )
            source_params = tuple(
                p for p in (_strip_param_name(p) for p in params) if p
            )
            if len(source_params) != len(entry.params):
                failures.append(
                    f"{path}:{definition.line}: {definition.name} arity "
                    f"{len(source_params)} != artifact {len(entry.params)}"
                )
                continue
            # The symbol table records const on parameter types but not on a
            # return type: `const char *Scope.name(...)` is stored as
            # `char *`. Comparing return qualifiers would therefore be
            # vacuous, so strip them on both sides.
            if _unqualified(ret) != _unqualified(entry.returns):
                failures.append(
                    f"{path}:{definition.line}: {definition.name} returns "
                    f"{ret!r} != artifact {entry.returns!r}"
                )
                continue
            mismatch = [
                (a, b) for a, b in zip(source_params, entry.params)
                if normalize_type(a) != normalize_type(b)
            ]
            if mismatch:
                failures.append(
                    f"{path}:{definition.line}: {definition.name} parameter "
                    f"types differ: {mismatch}"
                )
                continue
            checked += 1

    print(f"artifact version {symbols.version}, "
          f"snapshot hash {'matches' if ok_snapshot else 'DIFFERS'}")
    print(f"{matched}/{len(symbols.paths())} file content hashes match")
    print(f"{checked} lib signatures agree with the compiler's symbol table")
    if failures:
        print(f"\n{len(failures)} problem(s):", file=sys.stderr)
        for failure in failures[:40]:
            print(f"- {failure}", file=sys.stderr)
        return 1
    return 0


def _unqualified(text: str) -> str:
    """Normalize a type, dropping top-level const/volatile."""
    words = [w for w in normalize_type(text).split(" ")
             if w not in ("const", "volatile")]
    return " ".join(words)


def _strip_param_name(param: str) -> str:
    """Reduce `Array array` or `Var (*fn)(Var)` to its abstract type."""
    param = param.strip()
    if param in ("void", ""):
        return ""
    if param == "...":
        return "..."
    if "(" in param:
        # Function-pointer or array parameter: drop the identifier inside the
        # innermost declarator, e.g. Var (*fn)(Var) -> Var (*)(Var).
        return re.sub(r"(\(\s*\*+\s*)[A-Za-z_][A-Za-z0-9_]*(\s*\))",
                      r"\1\2", param)
    param = re.sub(r"\[\s*\]", " *", param)
    match = re.match(r"^(.*?)([A-Za-z_][A-Za-z0-9_]*)$", param)
    if not match:
        return param
    head, tail = match.group(1).strip(), match.group(2)
    if not head or tail in ("int", "char", "long", "short", "unsigned",
                            "signed", "float", "double", "void", "size_t",
                            "const"):
        return param
    return head


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        return selftest()
    symbols = load()
    print(f"header-symbols version {symbols.version}, "
          f"{len(symbols.paths())} files, snapshot {symbols.snapshot_hash}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
