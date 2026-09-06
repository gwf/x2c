#!/usr/bin/env python3
"""Rank x2c functions that deserve review for redundant validation."""

from __future__ import annotations

import argparse
import dataclasses
import json
import re
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[4] / "tools"
sys.path.insert(0, str(TOOLS))
from x2c_source import function_spans


SOURCE_SUFFIXES = {".x", ".xmacro"}
EXCLUDED_PATHS = {"lib/x2c.x"}
CONTROL_NAMES = {"catch", "for", "if", "match", "sizeof", "switch", "while"}
VALIDATOR_NAME_RE = re.compile(
    r"(?:^|[._])(?:check|compatible|require|valid|validate|validator|verify|"
    r"well_formed)(?:$|_)",
    re.IGNORECASE,
)
SHAPE_RE = re.compile(
    r"(?:\.(?:car|cdr|c[ad]{2,4}r|len)\s*\(|\.is\s*\(\s*<list>\s*\)|"
    r"\bis\s+(?:not\s+)?<list>|\bis\s+(?:not\s+)?List\b|"
    r"\btry_[A-Za-z0-9_]*parts\s*\()"
)
FRAMEWORK_REASONS = {
    "diagnostics are built around manual List or AST shape checks",
    "validator-like helper emits diagnostics",
    "validator-like helper inspects structural shape",
    "diagnostic validator recursively walks its input",
}


@dataclasses.dataclass(frozen=True)
class Function:
    path: str
    name: str
    start: int
    end: int
    masked: str
    body_start: int


@dataclasses.dataclass(frozen=True)
class Finding:
    path: str
    name: str
    start: int
    end: int
    score: int
    reasons: tuple[str, ...]

    @property
    def key(self) -> tuple[str, str]:
        return self.path, self.name


@dataclasses.dataclass(frozen=True)
class Framework:
    path: str
    start: int
    end: int
    lines: int
    functions: tuple[str, ...]
    reasons: tuple[str, ...]


@dataclasses.dataclass(frozen=True)
class TrustConsumer:
    path: str
    name: str
    line: int
    action: str
    score: int
    reasons: tuple[str, ...]


@dataclasses.dataclass(frozen=True)
class ProducerGroup:
    shape: str
    producers: tuple[str, ...]
    consumers: tuple[TrustConsumer, ...]


@dataclasses.dataclass(frozen=True)
class StaticMatchCapture:
    path: str
    name: str
    line: int
    bindings: tuple[str, ...]
    assoc_reads: int
    reasons: tuple[str, ...]


def _git(root: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", *args], cwd=root, text=True, stderr=subprocess.PIPE
    )


def repository_root() -> Path:
    try:
        return Path(_git(Path.cwd(), "rev-parse", "--show-toplevel").strip())
    except subprocess.CalledProcessError as error:
        raise SystemExit("run this command inside the x2c repository") from error


def mask_comments_and_literals(source: str) -> str:
    """Preserve offsets and newlines while blanking comments and literals."""
    output = list(source)
    index = 0
    while index < len(source):
        if source.startswith("//", index):
            end = source.find("\n", index)
            if end < 0:
                end = len(source)
            for cursor in range(index, end):
                output[cursor] = " "
            index = end
            continue
        if source.startswith("/*", index):
            close = source.find("*/", index + 2)
            end = len(source) if close < 0 else close + 2
            for cursor in range(index, end):
                if output[cursor] != "\n":
                    output[cursor] = " "
            index = end
            continue
        if source[index] in {'"', "'"}:
            quote = source[index]
            cursor = index + 1
            while cursor < len(source):
                if source[cursor] == "\\":
                    cursor += 2
                    continue
                if source[cursor] == quote:
                    cursor += 1
                    break
                cursor += 1
            for position in range(index, min(cursor, len(source))):
                if output[position] != "\n":
                    output[position] = " "
            index = cursor
            continue
        index += 1
    return "".join(output)


def _line_number(source: str, offset: int) -> int:
    return source.count("\n", 0, offset) + 1


def extract_functions(source: str, path: str) -> list[Function]:
    masked = mask_comments_and_literals(source)
    return [
        Function(
            path=path,
            name=span.name,
            start=_line_number(source, span.declaration_start),
            end=_line_number(source, span.end - 1),
            masked=masked[span.declaration_start:span.end],
            body_start=span.body_start - span.declaration_start,
        )
        for span in function_spans(masked, include_static=True)
    ]


def shared_error_causes(root: Path, revision: str | None = None) -> set[str]:
    path = "lib/error-macros.xmacro"
    try:
        source = _git(root, "show", f"{revision}:{path}") if revision else (
            root / path
        ).read_text(encoding="ascii")
    except (FileNotFoundError, subprocess.CalledProcessError):
        return set()
    match = re.search(
        r"error\.nonreturning\.causes\s+'\((.*?)\)\s*\)", source, re.DOTALL
    )
    if not match:
        return set()
    return set(re.findall(r"<([A-Za-z0-9_-]+)>", match.group(1)))


def _add_reason(reasons: list[str], reason: str, points: int) -> int:
    if reason in reasons:
        return 0
    reasons.append(reason)
    return points


def analyze_function(function: Function, causes: set[str]) -> Finding | None:
    body = function.masked
    reasons: list[str] = []
    score = 0

    if re.search(r"\.report_error\s*\([^;]*\)\s*;\s*return\b", body, re.DOTALL):
        score = max(
            score,
            _add_reason(reasons, "return follows non-returning report_error", 7),
        )

    for match in re.finditer(
        r"raise\s+%\(\s*([A-Za-z0-9_-]+)\b[^;]*;\s*return\b", body, re.DOTALL
    ):
        if match.group(1) in causes:
            score = max(
                score,
                _add_reason(
                    reasons,
                    "return follows a non-returning shared Error cause",
                    7,
                ),
            )
            break

    for match in re.finditer(
        r"\$error\.fallback\s*\([^)]*\)\s*raise\s+%\(\s*([A-Za-z0-9_-]+)\b",
        body,
        re.DOTALL,
    ):
        if match.group(1) in causes:
            score = max(
                score,
                _add_reason(
                    reasons,
                    "fallback wraps a non-returning shared Error cause",
                    7,
                ),
            )
            break

    literal_assignments = re.finditer(
        r"\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*%(?:\[\s*\]|\{\s*\})\s*;", body
    )
    for assignment in literal_assignments:
        name = assignment.group(1)
        null_guard = re.compile(
            rf"if\s*\(\s*\(void\s*\*\)\s*{re.escape(name)}\s*==\s*NULL\s*\)"
        )
        if null_guard.search(body, assignment.end()):
            score = max(
                score,
                _add_reason(
                    reasons,
                    "null guard checks a fresh Array or Map literal",
                    7,
                ),
            )
            break

    expected = re.findall(
        r"\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
        r"([A-Za-z_][A-Za-z0-9_.]*)\.(?:length|len\(\))\s*\+\s*1\s*;",
        body,
    )
    for expected_name, owner in expected:
        if re.search(rf"{re.escape(owner)}\.(?:append|push|insert)\s*\(", body) and re.search(
            rf"if\s*\([^)]*{re.escape(owner)}\.(?:length|len\(\))\s*!=\s*"
            rf"{re.escape(expected_name)}[^)]*\)\s*return\b",
            body,
        ):
            score = max(
                score,
                _add_reason(
                    reasons,
                    "checks whether a non-returning growth operation succeeded",
                    7,
                ),
            )
            break

    shape_count = len(SHAPE_RE.findall(body))
    branch_count = len(re.findall(r"\bif\s*\(", body))
    reports = len(re.findall(
        r"(?:\.report_error|\b[A-Za-z_][A-Za-z0-9_]*(?:fail|error)"
        r"[A-Za-z0-9_]*)\s*\(",
        body,
        re.IGNORECASE,
    ))
    validator_name = bool(VALIDATOR_NAME_RE.search(function.name))
    recursive = bool(re.search(
        rf"\b{re.escape(function.name)}\s*\(", body[function.body_start:]
    ))

    if reports and shape_count >= 3 and branch_count >= 2:
        score = max(
            score,
            _add_reason(
                reasons,
                "diagnostics are built around manual List or AST shape checks",
                4,
            ),
        )
    elif shape_count >= 3 and branch_count >= 2:
        score = max(
            score,
            _add_reason(
                reasons,
                "manual List or AST shape checks may be one static match",
                2,
            ),
        )

    if validator_name and reports:
        score = max(
            score,
            _add_reason(reasons, "validator-like helper emits diagnostics", 2),
        )
    elif validator_name and shape_count >= 2:
        score = max(
            score,
            _add_reason(
                reasons,
                "validator-like helper inspects structural shape",
                1,
            ),
        )

    if recursive and reports:
        score = max(
            score,
            _add_reason(
                reasons,
                "diagnostic validator recursively walks its input",
                3,
            ),
        )

    if not reasons:
        return None
    return Finding(
        path=function.path,
        name=function.name,
        start=function.start,
        end=function.end,
        score=score,
        reasons=tuple(reasons),
    )


def expand_paths(root: Path, arguments: list[str], revision: str | None) -> list[str]:
    requested = arguments or ["src", "lib"]
    if revision:
        candidates = _git(root, "ls-tree", "-r", "--name-only", revision).splitlines()
    else:
        candidates = _git(root, "ls-files").splitlines()
    found: set[str] = set()
    for candidate in candidates:
        path = Path(candidate)
        if path.suffix not in SOURCE_SUFFIXES or candidate in EXCLUDED_PATHS:
            continue
        for raw in requested:
            clean = raw.rstrip("/")
            if candidate == clean or candidate.startswith(clean + "/"):
                found.add(candidate)
                break
    return sorted(found)


def read_source(root: Path, path: str, revision: str | None) -> str:
    if revision:
        return _git(root, "show", f"{revision}:{path}")
    return (root / path).read_text(encoding="ascii")


def scan_functions(
    root: Path, paths: list[str], revision: str | None
) -> list[Function]:
    functions = []
    for path in expand_paths(root, paths, revision):
        source = read_source(root, path, revision)
        functions.extend(extract_functions(source, path))
    return functions


STATIC_MATCH_ASSIGN_RE = re.compile(
    r"(?:\bList\s+)?(?P<binding>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
    r"[^;]*?\.match\s*\(\s*%\(",
    re.DOTALL,
)
TAG_CHECK_RE = re.compile(
    r"\.car\s*\(\s*\)\s*(?:==|!=|is(?:\s+not)?)\s*<([A-Za-z0-9_-]+)>"
)
MATCH_HEAD_RE = re.compile(
    r"\bcase\s+%\(\s*(?:\(\s*!or\s+)?([A-Za-z_][A-Za-z0-9_-]*)"
)
CONSTRUCTOR_RE = re.compile(r"%\(\s*([A-Za-z_][A-Za-z0-9_-]*)")
CONS_TAG_RE = re.compile(r"\bcons\s*\(\s*<([A-Za-z0-9_-]+)>")
REGISTRY_READ_RE = re.compile(
    r"\b[A-Za-z_][A-Za-z0-9_]*\.([A-Za-z_][A-Za-z0-9_-]*)\.try_next\s*\("
)
REGISTRY_WRITE_RE = re.compile(
    r"\b[A-Za-z_][A-Za-z0-9_]*\.([A-Za-z_][A-Za-z0-9_]*)"
    r"\s*\[[^]]+\]\s*="
)
PARTS_RE = re.compile(r"\b(try_[A-Za-z0-9_]*parts)\s*\(")
CALL_RE = re.compile(r"(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_.]*)\s*\(")
TRUST_BOUNDARY_NAMES = {
    "Ast.try_sequence",
    "Compiler.rebuild_protocols",
    "_transform_cast",
    "_transform_defer_stmt",
    "_transform_return",
}


def _binding_escapes(body: str, binding: str, start: int) -> bool:
    tail = body[start:]
    if re.search(rf"\breturn\s+{re.escape(binding)}\b", tail):
        return True
    if re.search(rf"(?<![=!<>])=\s*{re.escape(binding)}\s*;", tail):
        return True
    for call in CALL_RE.finditer(tail):
        if call.group(1).split(".")[-1] in CONTROL_NAMES:
            continue
        opening = tail.find("(", call.start(), call.end())
        close = _matching_close(tail, opening, "(", ")")
        if close < 0:
            continue
        arguments = tail[opening + 1:close]
        if re.search(
            rf"(?:^|,)\s*{re.escape(binding)}\s*(?:,|$)", arguments
        ):
            return True
    return False


def find_static_match_captures(
    functions: list[Function],
) -> list[StaticMatchCapture]:
    """Find static List.match result objects read locally through assoc."""
    findings = []
    for function in functions:
        matches = list(STATIC_MATCH_ASSIGN_RE.finditer(function.masked))
        if not matches:
            continue
        by_binding: dict[str, list[re.Match[str]]] = {}
        for match in matches:
            by_binding.setdefault(match.group("binding"), []).append(match)
        bindings = []
        assoc_reads = 0
        first = None
        preflight = False
        for binding, assignments in by_binding.items():
            match = assignments[0]
            tail = function.masked[match.end():]
            reads = len(re.findall(
                rf"\b{re.escape(binding)}\.assoc\s*\(\s*<\?", tail
            ))
            if not reads or _binding_escapes(
                function.masked, binding, match.end()
            ):
                continue
            bindings.append(binding)
            assoc_reads += reads
            if first is None or match.start() < first:
                first = match.start()
            prefix = function.masked[:match.start()]
            if SHAPE_RE.search(prefix) or TAG_CHECK_RE.search(prefix):
                preflight = True
        if first is None:
            continue
        reasons = [
            f"{assoc_reads} local assoc read(s) unpack static List.match "
            "bindings"
        ]
        if preflight:
            reasons.append("manual List shape checks precede the static match")
        findings.append(StaticMatchCapture(
            path=function.path,
            name=function.name,
            line=function.start + function.masked.count("\n", 0, first),
            bindings=tuple(sorted(set(bindings))),
            assoc_reads=assoc_reads,
            reasons=tuple(reasons),
        ))
    return sorted(findings, key=lambda item: (item.path, item.line, item.name))


def _matching_close(text: str, start: int, opening: str, closing: str) -> int:
    depth = 0
    for offset in range(start, len(text)):
        if text[offset] == opening:
            depth += 1
        elif text[offset] == closing:
            depth -= 1
            if depth == 0:
                return offset
    return -1


def _silent_guards(function: Function) -> list[tuple[int, str, str]]:
    """Return line, condition, and silent action for structural if guards."""
    body = function.masked
    guards: list[tuple[int, str, str]] = []
    for found in re.finditer(r"\bif\s*\(", body):
        opening = body.find("(", found.start())
        close = _matching_close(body, opening, "(", ")")
        if close < 0:
            continue
        condition = body[opening + 1:close]
        if not (
            SHAPE_RE.search(condition)
            or TAG_CHECK_RE.search(condition)
            or re.search(r"\bis(?:\s+not)?\s+<list>", condition)
        ):
            continue
        cursor = close + 1
        while cursor < len(body) and body[cursor].isspace():
            cursor += 1
        if cursor < len(body) and body[cursor] == "{":
            end = _matching_close(body, cursor, "{", "}")
            consequence = body[cursor + 1:end if end >= 0 else len(body)]
        else:
            end = body.find(";", cursor)
            consequence = body[cursor:end + 1 if end >= 0 else len(body)]
        action = None
        if re.search(r"\bcontinue\s*;", consequence):
            action = "continue"
        elif re.search(r"\breturn\s+NULL\s*;", consequence):
            action = "return NULL"
        elif re.search(r"\breturn\s+0\s*;", consequence):
            action = "return 0"
        else:
            returned = re.search(r"\breturn\s+([^;]+);", consequence)
            if returned:
                expression = returned.group(1).strip()
                action = (
                    f"return {expression}"
                    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", expression)
                    else "return fallback"
                )
            elif re.search(
                r"\b[A-Za-z_][A-Za-z0-9_]*\s*=\s*[^=][^;]*;", consequence
            ):
                action = "use default"
        if action:
            line = function.start + body.count("\n", 0, found.start())
            guards.append((line, condition, action))
    return guards


def _shape_names(text: str) -> set[str]:
    shapes = set(TAG_CHECK_RE.findall(text))
    shapes.update(MATCH_HEAD_RE.findall(text))
    if re.search(r"\btry_binding_parts\s*\(", text):
        shapes.add("bind")
    if re.search(r"\bis(?:\s+not)?\s+<list>", text):
        shapes.add("list")
    shapes.update(REGISTRY_READ_RE.findall(text))
    return shapes


def _retains_partial_state(function: Function, action: str) -> bool:
    if action != "continue":
        return False
    return bool(re.search(
        r"(?:\.(?:push|append|insert)\s*\(|\[[^]]+\]\s*=)",
        function.masked,
    ))


def _constructed_shapes(function: Function) -> set[str]:
    shapes = set(CONS_TAG_RE.findall(function.masked))
    for found in CONSTRUCTOR_RE.finditer(function.masked):
        prefix = function.masked[max(0, found.start() - 12):found.start()]
        if not re.search(r"\bcase\s*$", prefix):
            shapes.add(found.group(1))
    return shapes


def _call_names(function: Function) -> set[str]:
    return {
        name for name in CALL_RE.findall(function.masked)
        if name.split(".")[-1] not in CONTROL_NAMES
    }


def _is_trust_boundary(function: Function) -> bool:
    if function.name in TRUST_BOUNDARY_NAMES:
        return True
    if function.name.startswith("_macro_sdk_"):
        return True
    if function.path == "src/collect.x" and "artifact" in function.name:
        return True
    return False


def _location(function: Function) -> str:
    return f"{function.path}:{function.start} {function.name}"


def _consumer_group(
    function: Function, condition: str, by_short: dict[str, list[Function]],
    upstream: set[str],
) -> tuple[str, set[str]]:
    registries = REGISTRY_READ_RE.findall(function.masked)
    if registries:
        registry = registries[0]
        return f"{registry} registry", {registry}
    helper = PARTS_RE.search(condition)
    if helper:
        name = helper.group(1)
        targets = by_short.get(name, [])
        label = targets[0].name if len(targets) == 1 else name
        return f"{label} result", set()
    if upstream:
        names = ", ".join(sorted(upstream))
        return f"values from {names}", set()
    return f"values passed to {function.name}", set()


def find_producer_groups(functions: list[Function]) -> list[ProducerGroup]:
    """Group silent downstream shape rejection by connected producers."""
    by_name = {function.name: function for function in functions}
    by_short: dict[str, list[Function]] = {}
    for function in functions:
        by_short.setdefault(function.name.split(".")[-1], []).append(function)

    callers: dict[str, set[str]] = {
        function.name: set() for function in functions
    }
    for caller in functions:
        for called in _call_names(caller):
            targets = by_short.get(called.split(".")[-1], [])
            for target in targets:
                callers[target.name].add(caller.name)

    constructors: dict[str, set[str]] = {}
    registry_writers: dict[str, set[str]] = {}
    for function in functions:
        for shape in _constructed_shapes(function):
            constructors.setdefault(shape, set()).add(_location(function))
        for registry in REGISTRY_WRITE_RE.findall(function.masked):
            registry_writers.setdefault(registry, set()).add(
                _location(function)
            )

    grouped: dict[str, list[TrustConsumer]] = {}
    producers: dict[str, set[str]] = {}
    for function in functions:
        if _is_trust_boundary(function):
            continue
        guards = _silent_guards(function)
        if not guards:
            continue
        for line, condition, action in guards:
            upstream = callers.get(function.name, set()) - {function.name}
            group, registries = _consumer_group(
                function, condition, by_short, upstream
            )
            shapes = _shape_names(condition) - {"list"}
            partial = _retains_partial_state(function, action)
            if partial:
                action = "continue with partial state"
            score = (
                6 if partial
                else 5 if action in {"continue", "return NULL"}
                else 4
            )
            reasons = [f"impossible shape can silently {action}"]
            if shapes:
                tags = ", ".join(f"<{shape}>" for shape in sorted(shapes))
                reasons.append(f"guard rechecks {tags}")
            if re.search(r"\bmatch\s*\(", function.masked):
                reasons.append(
                    "function also recognizes AST with source match"
                )
            if upstream:
                reasons.append(
                    "called by " + ", ".join(sorted(upstream))
                )
            consumer = TrustConsumer(
                path=function.path,
                name=function.name,
                line=line,
                action=action,
                score=score,
                reasons=tuple(reasons),
            )
            grouped.setdefault(group, []).append(consumer)
            for registry in registries:
                producers.setdefault(group, set()).update(
                    registry_writers.get(registry, set())
                )
            if not registries:
                for caller_name in upstream:
                    producers.setdefault(group, set()).add(
                        _location(by_name[caller_name])
                    )
            helper = PARTS_RE.search(condition)
            if helper:
                for target in by_short.get(helper.group(1), []):
                    producers.setdefault(group, set()).add(_location(target))
            if not producers.get(group) and shapes:
                candidates = set().union(
                    *(constructors.get(shape, set()) for shape in shapes)
                )
                if len(candidates) <= 8:
                    producers.setdefault(group, set()).update(candidates)

    groups = []
    for shape, consumers in grouped.items():
        unique = {
            (item.path, item.name, item.line, item.action): item
            for item in consumers
        }
        ordered = tuple(sorted(
            unique.values(),
            key=lambda item: (-item.score, item.path, item.line, item.name),
        ))
        groups.append(ProducerGroup(
            shape=shape,
            producers=tuple(sorted(producers.get(shape, set()))),
            consumers=ordered,
        ))
    return sorted(
        groups,
        key=lambda group: (
            -max(item.score for item in group.consumers),
            -len(group.consumers),
            group.shape,
        ),
    )


def find_frameworks(functions: list[Function], causes: set[str]) -> list[Framework]:
    by_path: dict[str, list[tuple[Function, Finding]]] = {}
    for function in functions:
        finding = analyze_function(function, causes)
        if not finding or not (set(finding.reasons) & FRAMEWORK_REASONS):
            continue
        by_path.setdefault(function.path, []).append((function, finding))

    frameworks = []
    for path, candidates in by_path.items():
        by_name = {function.name: (function, finding)
                   for function, finding in candidates}
        neighbors = {name: set() for name in by_name}
        for name, (function, _) in by_name.items():
            for other in by_name:
                if other == name:
                    continue
                call = re.compile(
                    rf"(?<![A-Za-z0-9_.]){re.escape(other)}\s*\("
                )
                if call.search(function.masked):
                    neighbors[name].add(other)
                    neighbors[other].add(name)

        remaining = set(by_name)
        while remaining:
            seed = min(remaining)
            stack = [seed]
            component = set()
            while stack:
                name = stack.pop()
                if name in component:
                    continue
                component.add(name)
                stack.extend(neighbors[name] - component)
            remaining -= component

            members = [by_name[name] for name in component]
            lines = sum(function.end - function.start + 1
                        for function, _ in members)
            recursive = any(
                "diagnostic validator recursively walks its input"
                in finding.reasons
                for _, finding in members
            )
            named_validator = any(
                VALIDATOR_NAME_RE.search(function.name)
                for function, _ in members
            )
            if (not named_validator or lines < 40
                    or (len(members) < 2 and not recursive)):
                continue
            reasons = sorted({
                reason
                for _, finding in members
                for reason in finding.reasons
                if reason in FRAMEWORK_REASONS
            })
            frameworks.append(Framework(
                path=path,
                start=min(function.start for function, _ in members),
                end=max(function.end for function, _ in members),
                lines=lines,
                functions=tuple(sorted(component)),
                reasons=tuple(reasons),
            ))
    return sorted(
        frameworks,
        key=lambda item: (-item.lines, item.path, item.start),
    )


def scan(
    root: Path, paths: list[str], revision: str | None, minimum: int
) -> list[Finding]:
    causes = shared_error_causes(root, revision)
    findings: list[Finding] = []
    for path in expand_paths(root, paths, revision):
        source = read_source(root, path, revision)
        for function in extract_functions(source, path):
            finding = analyze_function(function, causes)
            if finding and finding.score >= minimum:
                findings.append(finding)
    return sorted(findings, key=lambda item: (-item.score, item.path, item.start))


def diagnostic_fixture_changes(root: Path, comparison: str) -> list[str]:
    output = _git(
        root,
        "diff",
        "--name-status",
        comparison,
        "--",
        "unittest/compiler-fixtures",
    )
    families: set[str] = set()
    for line in output.splitlines():
        fields = line.split("\t")
        if len(fields) != 2 or fields[0] != "D":
            continue
        path = Path(fields[1])
        if path.suffix in {".diagnostics", ".compile-status", ".phases", ".x"}:
            families.add(path.with_suffix("").as_posix())
    return sorted(families)


def finding_dict(finding: Finding) -> dict[str, object]:
    return dataclasses.asdict(finding)


def print_findings(findings: list[Finding], details: bool, limit: int) -> None:
    visible = findings if limit == 0 else findings[:limit]
    print(f"{'score':>5}  {'location':<48}  function")
    for finding in visible:
        location = f"{finding.path}:{finding.start}"
        print(f"{finding.score:>5}  {location:<48}  {finding.name}")
        if details:
            for reason in finding.reasons:
                print(f"       - {reason}")
    print(f"\n{len(findings)} candidate functions; review the source before deleting anything")


def print_frameworks(frameworks: list[Framework], details: bool,
                     limit: int) -> None:
    visible = frameworks if limit == 0 else frameworks[:limit]
    print(f"{'lines':>5}  {'location':<48}  connected functions")
    for framework in visible:
        location = f"{framework.path}:{framework.start}-{framework.end}"
        names = ", ".join(framework.functions)
        print(f"{framework.lines:>5}  {location:<48}  {names}")
        if details:
            for reason in framework.reasons:
                print(f"       - {reason}")
    print(
        f"\n{len(frameworks)} connected validation frameworks; "
        "trace production consumers before deleting anything"
    )


def print_producer_groups(groups: list[ProducerGroup], details: bool,
                          limit: int) -> None:
    visible = groups if limit == 0 else groups[:limit]
    for group in visible:
        print(group.shape)
        if group.producers:
            for producer in group.producers:
                print(f"  produced by {producer}")
        else:
            print("  producer not resolved mechanically")
        for consumer in group.consumers:
            print(
                f"  {consumer.score}  {consumer.path}:{consumer.line}  "
                f"{consumer.name}: {consumer.action}"
            )
            if details:
                for reason in consumer.reasons:
                    print(f"       - {reason}")
        print()
    count = sum(len(group.consumers) for group in groups)
    print(
        f"{len(groups)} producer groups with {count} silent guards; "
        "trace each producer before deleting anything"
    )


def print_static_match_captures(findings: list[StaticMatchCapture],
                                details: bool, limit: int) -> None:
    visible = findings if limit == 0 else findings[:limit]
    print(f"{'location':<48}  function")
    for finding in visible:
        location = f"{finding.path}:{finding.line}"
        print(f"{location:<48}  {finding.name}")
        if details:
            for reason in finding.reasons:
                print(f"       - {reason}")
    print(
        f"\n{len(findings)} static match capture candidates; "
        "use source match when captures stay in one branch"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="tracked .x or .xmacro paths")
    parser.add_argument("--rev", help="scan one Git revision instead of the worktree")
    parser.add_argument(
        "--compare", metavar="OLD..NEW", help="show candidates removed or added"
    )
    parser.add_argument("--min-score", type=int, default=3)
    parser.add_argument("--limit", type=int, default=30, help="0 shows every result")
    parser.add_argument("--details", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument(
        "--frameworks",
        action="store_true",
        help="show connected validator families ranked by authored lines",
    )
    parser.add_argument(
        "--producer-consumers",
        action="store_true",
        help="group silent shape guards by connected value producers",
    )
    parser.add_argument(
        "--static-match-captures",
        action="store_true",
        help="show static List.match bindings unpacked locally with assoc",
    )
    args = parser.parse_args(argv)
    if args.compare and args.rev:
        parser.error("--compare and --rev cannot be combined")
    if args.compare and args.frameworks:
        parser.error("--compare and --frameworks cannot be combined")
    if args.compare and args.producer_consumers:
        parser.error("--compare and --producer-consumers cannot be combined")
    if args.compare and args.static_match_captures:
        parser.error("--compare and --static-match-captures cannot be combined")
    modes = sum((
        args.frameworks,
        args.producer_consumers,
        args.static_match_captures,
    ))
    if modes > 1:
        parser.error("audit modes cannot be combined")
    if args.min_score < 1:
        parser.error("--min-score must be positive")

    root = repository_root()
    if args.static_match_captures:
        functions = scan_functions(root, args.paths, args.rev)
        findings = find_static_match_captures(functions)
        if args.json:
            print(json.dumps({
                "revision": args.rev,
                "static_match_captures": [
                    dataclasses.asdict(item) for item in findings
                ],
            }, indent=2))
        else:
            print_static_match_captures(findings, args.details, args.limit)
        return 0
    if args.producer_consumers:
        functions = scan_functions(root, args.paths, args.rev)
        groups = find_producer_groups(functions)
        if args.json:
            print(json.dumps({
                "revision": args.rev,
                "producer_groups": [
                    dataclasses.asdict(item) for item in groups
                ],
            }, indent=2))
        else:
            print_producer_groups(groups, args.details, args.limit)
        return 0
    if args.frameworks:
        functions = scan_functions(root, args.paths, args.rev)
        frameworks = find_frameworks(
            functions, shared_error_causes(root, args.rev)
        )
        if args.json:
            print(json.dumps({
                "revision": args.rev,
                "frameworks": [dataclasses.asdict(item) for item in frameworks],
            }, indent=2))
        else:
            print_frameworks(frameworks, args.details, args.limit)
        return 0
    if args.compare:
        if args.compare.count("..") != 1:
            parser.error("--compare must be OLD..NEW")
        old, new = args.compare.split("..", 1)
        before = scan(root, args.paths, old, args.min_score)
        after = scan(root, args.paths, new, args.min_score)
        before_map = {item.key: item for item in before}
        after_map = {item.key: item for item in after}
        removed = [before_map[key] for key in before_map.keys() - after_map.keys()]
        added = [after_map[key] for key in after_map.keys() - before_map.keys()]
        removed.sort(key=lambda item: (-item.score, item.path, item.start))
        added.sort(key=lambda item: (-item.score, item.path, item.start))
        fixtures = diagnostic_fixture_changes(root, args.compare)
        if args.json:
            print(json.dumps({
                "comparison": args.compare,
                "removed": [finding_dict(item) for item in removed],
                "added": [finding_dict(item) for item in added],
                "removed_diagnostic_fixture_families": fixtures,
            }, indent=2))
            return 0
        print("Removed candidates")
        print_findings(removed, args.details, args.limit)
        print("\nAdded candidates")
        print_findings(added, args.details, args.limit)
        if fixtures:
            print("\nRemoved diagnostic fixture families")
            for fixture in fixtures:
                print(f"  {fixture}")
        return 0

    findings = scan(root, args.paths, args.rev, args.min_score)
    if args.json:
        print(json.dumps({
            "revision": args.rev,
            "findings": [finding_dict(item) for item in findings],
        }, indent=2))
    else:
        print_findings(findings, args.details, args.limit)
    return 0


if __name__ == "__main__":
    sys.exit(main())
