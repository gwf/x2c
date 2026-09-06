#!/usr/bin/env python3
"""Find mechanically suspicious areas in x2c production source.

The audit is deliberately source-only. It reports places worth reading; it
does not decide that a design is wrong. Its score measures detector strength,
not architectural value, deletable lines, or review priority.
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import math
import pathlib
import re
import sys
from dataclasses import dataclass, field
from typing import Iterable

from x2c_source import function_spans, mask_non_code


FORMAT_VERSION = 1
COMPONENT_CAPS = {
    "repeated_representation": 25,
    "extra_machinery": 20,
    "manual_bookkeeping": 15,
    "repeated_routes": 15,
    "cosmetics": 10,
    "size_vs_use": 15,
}
RULES = {
    "format_version": FORMAT_VERSION,
    "detector_revision": 2,
    "component_caps": COMPONENT_CAPS,
    "merge_distance": 40,
    "route_similarity": "4/5",
    "contributions": {
        "ordinal_table_switch": 25,
        "shared_identifier": 1,
        "field_transfer": 2,
        "whole_struct_copy": 5,
        "internal_type": "1+ceil(members/4), max 5",
        "lifecycle_pair": 2,
        "ordinal_cases": "floor(cases/8)",
        "statistics_sites": "floor(sites/5)",
        "cleanup_sites": "floor(sites/5)",
        "repeated_route": "3*(functions-1)+floor(lines/40)",
        "duplicate_function_body": "3*(functions-1)+floor(lines/40)",
        "cosmetic_prose": "floor(findings/4), max 6",
        "cosmetic_width": "findings, max 2",
        "cosmetic_blanks": "findings, max 2",
        "size_vs_use": "floor(lines/40)-external call sites",
    },
}
RULES_DIGEST = hashlib.sha256(
    json.dumps(RULES, sort_keys=True, separators=(",", ":")).encode()
).hexdigest()

TYPE_RE = re.compile(
    r"(?m)^[ \t]*(?:static[ \t]+)?(?:typedef[ \t]+)?"
    r"(?P<kind>struct|enum|protocol)[ \t]+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)[ \t]*\{"
)
IDENT_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
CALL_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_.]*)\s*\(")
NARRATION_RE = re.compile(
    r"\b(?:note that|important(?:ly)?|in order to|for completeness|"
    r"at this point|we (?:need|want|must|can)|this (?:function|code) "
    r"(?:will|is responsible for)|simply|obviously|basically)\b",
    re.IGNORECASE,
)
PROHIBITED_RE = re.compile(
    r"\b(?:contract|boundary|ledger|ontology|orchestrat(?:e|ion)|"
    r"schema-driven|robustness|future-proof)\b",
    re.IGNORECASE,
)
RULER_RE = re.compile(r"^\s*(?://|/\*+|\*)?\s*[-=*_]{8,}\s*(?:\*/)?\s*$")
STAT_RE = re.compile(
    r"\b(?:stat(?:s|istics)?|count(?:er)?|hits|misses|total)\b[^;\n]*"
    r"(?:\+\+|--|\+=|-=|=)",
    re.IGNORECASE,
)
CLEANUP_RE = re.compile(
    r"\b(?:free|dispose|release|cleanup|close|unpin|rollback)\s*\("
)
PAIR_WORDS = (
    ("acquire", "release"),
    ("begin", "commit"),
    ("begin", "rollback"),
    ("pin", "unpin"),
    ("open", "dispose"),
)


@dataclass(frozen=True)
class Source:
    path: str
    raw: str
    code: str

    def line(self, offset: int) -> int:
        return self.raw.count("\n", 0, offset) + 1


@dataclass
class Area:
    detectors: set[str]
    paths: dict[str, list[tuple[int, int]]]
    names: set[str]
    components: dict[str, int] = field(default_factory=dict)
    raw_counts: dict[str, int] = field(default_factory=dict)
    evidence: set[str] = field(default_factory=set)
    callable_names: set[str] = field(default_factory=set)

    def add(self, component: str, amount: int) -> None:
        self.components[component] = self.components.get(component, 0) + amount


def _brace_end(text: str, opening: int) -> int:
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return index + 1
    return -1


def _line_range(source: Source, start: int, end: int) -> tuple[int, int]:
    return source.line(start), source.line(max(start, end - 1))


def _depths(text: str) -> list[int]:
    depths = [0] * (len(text) + 1)
    depth = 0
    for index, char in enumerate(text):
        depths[index] = depth
        if char == "{":
            depth += 1
        elif char == "}":
            depth = max(0, depth - 1)
    depths[len(text)] = depth
    return depths


def _area(
    detector: str,
    source: Source,
    start: int,
    end: int,
    names: Iterable[str],
) -> Area:
    return Area(
        {detector},
        {source.path: [_line_range(source, start, end)]},
        set(names),
    )


def _functions(source: Source) -> list[tuple[str, int, int, str]]:
    return [
        (span.name, span.declaration_start, span.end,
         source.code[span.body_start:span.end - 1])
        for span in function_spans(source.code, include_static=True)
    ]


def _types(source: Source) -> list[tuple[str, str, int, int, int]]:
    found = []
    depths = _depths(source.code)
    for match in TYPE_RE.finditer(source.code):
        if depths[match.start()]:
            continue
        opening = source.code.find("{", match.start(), match.end())
        end = _brace_end(source.code, opening)
        if end < 0:
            continue
        body = source.code[opening + 1:end - 1]
        if match.group("kind") == "enum":
            members = len([
                part for part in body.split(",")
                if IDENT_RE.search(part)
            ])
        else:
            members = body.count(";")
        found.append((match.group("kind"), match.group("name"),
                      match.start(), end, members))
    return found


def _ordinal_areas(source: Source) -> list[Area]:
    areas = []
    switch_re = re.compile(r"\bswitch\s*\([^)]*\)\s*\{")
    case_re = re.compile(
        r"\bcase\s+([A-Za-z_][A-Za-z0-9_]*)\s*:"
        r"(?:(?!\bcase\b|\bdefault\b)[\s\S])*?"
        r"\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\d+)\s*;"
    )
    table_re = re.compile(
        r"(?m)^[ \t]*(?:static[ \t]+)?(?:const[ \t]+)?"
        r"[A-Za-z_][A-Za-z0-9_.$<>* \t]+[ \t]+"
        r"([A-Za-z_][A-Za-z0-9_]*)[ \t]*\[[^\]\n]*\]"
        r"[ \t]*=[ \t]*\{"
    )
    tables = list(table_re.finditer(source.code))
    for switch in switch_re.finditer(source.code):
        opening = source.code.find("{", switch.start(), switch.end())
        end = _brace_end(source.code, opening)
        if end < 0:
            continue
        cases = list(case_re.finditer(source.code, opening, end))
        if len(cases) < 8:
            continue
        variables = {case.group(2) for case in cases}
        values = [int(case.group(3)) for case in cases]
        if len(variables) != 1 or values != list(range(values[0],
                                                       values[0] + len(values))):
            continue
        index_name = next(iter(variables))
        candidates = [table for table in tables if table.start() < switch.start()]
        indexed = []
        for table in candidates:
            name = table.group(1)
            if re.search(rf"\b{re.escape(name)}\s*\[\s*{re.escape(index_name)}\s*\]",
                         source.code[switch.start():]):
                indexed.append(table)
        if not indexed:
            continue
        table = indexed[-1]
        names = {index_name, table.group(1)} | {case.group(1) for case in cases}
        area = _area("ordinal-table-switch", source, table.start(), end, names)
        area.add("repeated_representation", 25)
        area.add("manual_bookkeeping", len(cases) // 8)
        area.raw_counts["ordinal_cases"] = len(cases)
        area.raw_counts["ordinal_table_switches"] = 1
        area.evidence.add(
            f"{len(cases)} sequential cases select {table.group(1)}"
        )
        areas.append(area)
    return areas


def _enum_table_switch_areas(source: Source) -> list[Area]:
    areas = []
    tables = []
    table_re = re.compile(
        r"(?m)^[ \t]*(?:static[ \t]+)?(?:const[ \t]+)?"
        r"[A-Za-z_][A-Za-z0-9_.$<>* \t]+[ \t]+"
        r"([A-Za-z_][A-Za-z0-9_]*)[ \t]*\[[^\]\n]*\]"
        r"[ \t]*=[ \t]*\{"
    )
    for match in table_re.finditer(source.code):
        opening = source.code.find("{", match.start(), match.end())
        end = _brace_end(source.code, opening)
        if end > 0:
            tables.append((match.group(1), match.start(), end,
                           set(IDENT_RE.findall(source.code[opening:end]))))
    switches = []
    for match in re.finditer(r"\bswitch\s*\([^)]*\)\s*\{", source.code):
        opening = source.code.find("{", match.start(), match.end())
        end = _brace_end(source.code, opening)
        if end > 0:
            names = set(re.findall(
                r"\bcase\s+([A-Za-z_][A-Za-z0-9_]*)\s*:",
                source.code[opening:end],
            ))
            switches.append((match.start(), end, names))
    for kind, enum_name, start, end, _ in _types(source):
        if kind != "enum":
            continue
        enum_names = set(IDENT_RE.findall(source.code[start:end]))
        for table_name, table_start, table_end, table_names in tables:
            first = enum_names & table_names
            if len(first) < 3:
                continue
            for switch_start, switch_end, switch_names in switches:
                shared = first & switch_names
                if len(shared) < 3:
                    continue
                names = shared | {enum_name, table_name}
                area = _area(
                    "enum-table-switch", source,
                    min(start, table_start, switch_start),
                    max(end, table_end, switch_end), names,
                )
                area.add("repeated_representation", len(shared))
                area.raw_counts["shared_identifiers"] = len(shared)
                area.evidence.add(
                    f"{len(shared)} identifiers recur in enum, table, and switch"
                )
                areas.append(area)
    return areas


def _copy_areas(source: Source) -> list[Area]:
    areas = []
    transfer_re = re.compile(
        r"\b([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
        r"([A-Za-z_][A-Za-z0-9_]*)\.\2\s*;"
    )
    whole_re = re.compile(
        r"(?:\*\s*)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
        r"(?:\*\s*)?([A-Za-z_][A-Za-z0-9_]*)\s*;"
    )
    for function, start, end, body in _functions(source):
        transfers = list(transfer_re.finditer(body))
        whole = [match for match in whole_re.finditer(body)
                 if "*" in match.group(0)]
        if not transfers and not whole:
            continue
        names = {function}
        names.update(match.group(2) for match in transfers)
        area = _area("struct-copy", source, start, end, names)
        if transfers:
            area.add("repeated_representation", 2 * len(transfers))
            area.raw_counts["same_name_field_transfers"] = len(transfers)
        if whole:
            area.add("repeated_representation", 5 * len(whole))
            area.raw_counts["whole_struct_copies"] = len(whole)
        area.evidence.add(
            f"{len(transfers)} field transfers and {len(whole)} whole copies"
        )
        area.callable_names.add(function)
        areas.append(area)
    return areas


def _internal_type_areas(sources: list[Source]) -> list[Area]:
    areas = []
    for source in sources:
        for kind, name, start, end, members in _types(source):
            outside = sum(
                len(re.findall(rf"\b{re.escape(name)}\b", other.code))
                for other in sources if other.path != source.path
            )
            if outside:
                continue
            points = min(5, 1 + math.ceil(members / 4))
            area = _area("internal-type", source, start, end, {name})
            area.add("extra_machinery", points)
            area.raw_counts["internal_types"] = 1
            area.raw_counts["type_members"] = members
            area.evidence.add(
                f"{kind} {name} has {members} members and no production use "
                "outside its file"
            )
            areas.append(area)
    return areas


def _lifecycle_areas(source: Source) -> list[Area]:
    functions = _functions(source)
    lowered = {name.lower(): (name, start, end) for name, start, end, _ in functions}
    areas = []
    seen = set()
    for left, right in PAIR_WORDS:
        for low_name, (name, start, end) in lowered.items():
            at = low_name.rfind(left)
            if at < 0:
                continue
            mate = low_name[:at] + right + low_name[at + len(left):]
            if mate not in lowered:
                continue
            other, other_start, other_end = lowered[mate]
            key = tuple(sorted((name, other)))
            if key in seen:
                continue
            seen.add(key)
            area = _area(
                "lifecycle-pair", source, min(start, other_start),
                max(end, other_end), key,
            )
            area.add("extra_machinery", 2)
            area.raw_counts["lifecycle_pairs"] = 1
            area.evidence.add(f"paired {left}/{right} functions")
            area.callable_names.update(key)
            areas.append(area)
    return areas


def _bookkeeping_areas(source: Source) -> list[Area]:
    areas = []
    for function, start, end, body in _functions(source):
        stats = len(STAT_RE.findall(body))
        cleanup = len(CLEANUP_RE.findall(body))
        if stats < 5 and cleanup < 5:
            continue
        area = _area("manual-bookkeeping", source, start, end, {function})
        if stats:
            area.add("manual_bookkeeping", stats // 5)
            area.raw_counts["statistics_sites"] = stats
        if cleanup:
            area.add("manual_bookkeeping", cleanup // 5)
            area.raw_counts["cleanup_sites"] = cleanup
        area.evidence.add(
            f"{stats} statistics sites and {cleanup} cleanup calls"
        )
        area.callable_names.add(function)
        areas.append(area)
    return areas


def _route_tokens(body: str) -> tuple[tuple[str, ...], int]:
    controls = re.findall(r"\b(?:if|else|for|while|switch|case|match|return)\b",
                          body)
    calls = [name.rsplit(".", 1)[-1] for name in CALL_RE.findall(body)
             if name not in {"if", "for", "while", "switch", "match"}]
    return tuple(controls + calls), body.count("\n") + 1


def _similar(left: tuple[str, ...], right: tuple[str, ...]) -> bool:
    if not left or not right:
        return False
    ratio = difflib.SequenceMatcher(
        None, left, right, autojunk=False
    ).ratio()
    return ratio >= 0.8


def _route_areas(source: Source) -> list[Area]:
    functions = []
    for name, start, end, body in _functions(source):
        tokens, lines = _route_tokens(body)
        if len(tokens) >= 3:
            functions.append((name, start, end, tokens, lines))
    neighbors = {index: set() for index in range(len(functions))}
    for left in range(len(functions)):
        for right in range(left + 1, len(functions)):
            if _similar(functions[left][3], functions[right][3]):
                neighbors[left].add(right)
                neighbors[right].add(left)
    areas = []
    remaining = set(range(len(functions)))
    while remaining:
        seed = min(remaining)
        stack = [seed]
        group = set()
        while stack:
            current = stack.pop()
            if current in group:
                continue
            group.add(current)
            stack.extend(neighbors[current] & remaining)
        remaining -= group
        if len(group) < 3:
            continue
        entries = [functions[index] for index in sorted(group)]
        repeated_lines = min(entry[4] for entry in entries) * len(entries)
        points = 3 * (len(entries) - 1) + repeated_lines // 40
        names = {entry[0] for entry in entries}
        area = _area(
            "repeated-routes", source, min(entry[1] for entry in entries),
            max(entry[2] for entry in entries), names,
        )
        area.add("repeated_routes", points)
        area.raw_counts["repeated_functions"] = len(entries)
        area.raw_counts["repeated_lines"] = repeated_lines
        area.evidence.add(
            f"{len(entries)} functions share at least 80% of control/call tokens"
        )
        area.callable_names.update(names)
        areas.append(area)
    return areas


def _duplicate_function_areas(sources: list[Source]) -> list[Area]:
    groups: dict[str, list[tuple[Source, str, int, int, int]]] = {}
    for source in sources:
        for name, start, end, function in _functions(source):
            body = re.sub(r"\s+", " ", function).strip()
            lines = source.code[start:end].count("\n") + 1
            if len(body) < 80 or lines < 5:
                continue
            groups.setdefault(body, []).append(
                (source, name, start, end, lines)
            )

    areas = []
    for entries in groups.values():
        if len({entry[0].path for entry in entries}) < 2:
            continue
        repeated_lines = min(entry[4] for entry in entries) * len(entries)
        area = Area({"duplicate-function-body"}, {}, set())
        for source, name, start, end, _ in entries:
            area.paths.setdefault(source.path, []).append(
                _line_range(source, start, end)
            )
            area.names.add(name)
            area.callable_names.add(name)
        area.add(
            "repeated_routes",
            3 * (len(entries) - 1) + repeated_lines // 40,
        )
        functions = len(entries)
        files = len({
            entry[0].path for entry in entries
        })
        area.raw_counts["duplicate_functions"] = functions
        area.raw_counts["duplicate_files"] = files
        area.raw_counts["repeated_lines"] = repeated_lines
        area.evidence.add(
            f"{functions} functions in {files} files have the same body"
        )
        areas.append(area)
    return areas


def _cosmetic_areas(source: Source) -> list[Area]:
    prose = []
    width = []
    blanks = []
    run = 0
    for number, line in enumerate(source.raw.splitlines(), 1):
        if NARRATION_RE.search(line) or PROHIBITED_RE.search(line) or RULER_RE.match(line):
            prose.append(number)
        if len(line) > 79:
            width.append(number)
        if line.strip():
            run = 0
        else:
            run += 1
            if run == 3:
                blanks.append(number - 2)
    if not prose and not width and not blanks:
        return []
    lines = prose + width + blanks
    area = Area(
        {"cosmetics"}, {source.path: [(min(lines), max(lines))]},
        {pathlib.PurePosixPath(source.path).stem},
    )
    prose_points = min(6, len(prose) // 4)
    width_points = min(2, len(width))
    blank_points = min(2, len(blanks))
    area.add("cosmetics", prose_points + width_points + blank_points)
    area.raw_counts.update({
        "cosmetic_prose": len(prose),
        "long_lines": len(width),
        "blank_line_runs": len(blanks),
    })
    if prose:
        area.evidence.add(f"{len(prose)} narration, prose, or ruler findings")
    if width:
        area.evidence.add(f"{len(width)} lines exceed 79 columns")
    if blanks:
        area.evidence.add(f"{len(blanks)} runs of at least three blank lines")
    return [area]


def _ranges_touch(left: list[tuple[int, int]],
                  right: list[tuple[int, int]]) -> bool:
    return any(a <= d + 40 and c <= b + 40
               for a, b in left for c, d in right)


def _mergeable(left: Area, right: Area) -> bool:
    if not left.names & right.names:
        return False
    return any(
        path in right.paths and _ranges_touch(ranges, right.paths[path])
        for path, ranges in left.paths.items()
    )


def _merge(left: Area, right: Area) -> Area:
    left.detectors |= right.detectors
    left.names |= right.names
    left.evidence |= right.evidence
    left.callable_names |= right.callable_names
    for path, ranges in right.paths.items():
        left.paths.setdefault(path, []).extend(ranges)
    for name, value in right.components.items():
        left.components[name] = left.components.get(name, 0) + value
    for name, value in right.raw_counts.items():
        left.raw_counts[name] = left.raw_counts.get(name, 0) + value
    return left


def _merge_areas(areas: list[Area]) -> list[Area]:
    ordered = sorted(areas, key=lambda area: (
        sorted(area.paths), min(min(r) for ranges in area.paths.values()
                                for r in ranges), sorted(area.detectors),
    ))
    changed = True
    while changed:
        changed = False
        result = []
        while ordered:
            area = ordered.pop(0)
            for index, other in enumerate(ordered):
                if _mergeable(area, other):
                    area = _merge(area, ordered.pop(index))
                    changed = True
                    break
            result.append(area)
        ordered = result
    return ordered


def _coalesce(ranges: list[tuple[int, int]]) -> list[tuple[int, int]]:
    result = []
    for start, end in sorted(ranges):
        if result and start <= result[-1][1] + 1:
            result[-1] = (result[-1][0], max(result[-1][1], end))
        else:
            result.append((start, end))
    return result


def _outside_calls(area: Area, sources: list[Source]) -> int:
    count = 0
    for name in area.callable_names:
        short = name.rsplit(".", 1)[-1]
        pattern = re.compile(rf"\b{re.escape(short)}\s*\(")
        for source in sources:
            masked = source.code
            for start, end in area.paths.get(source.path, []):
                lines = masked.splitlines(keepends=True)
                first = sum(len(line) for line in lines[:start - 1])
                last = sum(len(line) for line in lines[:end])
                masked = masked[:first] + " " * (last - first) + masked[last:]
            count += len(pattern.findall(masked))
    return count


def _finish(area: Area, sources: list[Source]) -> dict:
    ranges = {path: _coalesce(values)
              for path, values in sorted(area.paths.items())}
    suspicious_lines = sum(end - start + 1 for values in ranges.values()
                           for start, end in values)
    calls = _outside_calls(area, sources)
    size_points = max(0, suspicious_lines // 40 - calls)
    if size_points:
        area.components["size_vs_use"] = size_points
    area.raw_counts["suspicious_lines"] = suspicious_lines
    area.raw_counts["external_non_test_call_sites"] = calls
    components = {
        name: min(COMPONENT_CAPS[name], area.components.get(name, 0))
        for name in COMPONENT_CAPS
    }
    score = min(100, sum(components.values()))
    identity = json.dumps({
        "detectors": sorted(area.detectors),
        "paths": sorted(ranges),
        "names": sorted(area.names),
    }, sort_keys=True, separators=(",", ":"))
    stable_id = "bloat-" + hashlib.sha256(identity.encode()).hexdigest()[:16]
    return {
        "id": stable_id,
        "detectors": sorted(area.detectors),
        "paths": [
            {"path": path,
             "ranges": [[start, end] for start, end in values]}
            for path, values in ranges.items()
        ],
        "declarations": sorted(area.names),
        "score": score,
        "components": components,
        "raw_counts": dict(sorted(area.raw_counts.items())),
        "evidence": sorted(area.evidence),
    }


def _resolve(root: pathlib.Path, inputs: Iterable[str] | None) -> list[pathlib.Path]:
    root = root.resolve()
    candidates = []
    if not inputs:
        candidates.extend((root / "src").glob("*.x"))
        candidates.extend((root / "lib").glob("*.x"))
    else:
        for value in inputs:
            supplied = pathlib.Path(value)
            path = supplied if supplied.is_absolute() else root / supplied
            try:
                path = path.resolve(strict=True)
            except OSError as error:
                raise ValueError(f"input does not exist: {value}") from error
            if path != root and root not in path.parents:
                raise ValueError(f"input is outside repository: {value}")
            if path.is_dir():
                candidates.extend(path.glob("*.x"))
            elif path.suffix == ".x":
                candidates.append(path)
            else:
                raise ValueError(f"input is not an .x file or directory: {value}")
    paths = []
    for path in candidates:
        path = path.resolve()
        relative = path.relative_to(root).as_posix()
        if relative == "lib/x2c.x":
            continue
        paths.append(path)
    return sorted(set(paths), key=lambda path: path.relative_to(root).as_posix())


def analyze(root: pathlib.Path, inputs: Iterable[str] | None = None) -> dict:
    root = root.resolve()
    paths = _resolve(root, inputs)
    if not paths:
        raise ValueError("no .x source files found")
    sources = []
    digest = hashlib.sha256()
    for path in paths:
        relative = path.relative_to(root).as_posix()
        try:
            data = path.read_bytes()
            raw = data.decode("utf-8")
        except UnicodeDecodeError as error:
            raise ValueError(f"source is not UTF-8: {relative}") from error
        digest.update(relative.encode())
        digest.update(b"\0")
        digest.update(data)
        digest.update(b"\0")
        sources.append(Source(relative, raw, mask_non_code(raw)))

    areas = []
    for source in sources:
        areas.extend(_ordinal_areas(source))
        areas.extend(_enum_table_switch_areas(source))
        areas.extend(_copy_areas(source))
        areas.extend(_lifecycle_areas(source))
        areas.extend(_bookkeeping_areas(source))
        areas.extend(_route_areas(source))
        areas.extend(_cosmetic_areas(source))
    areas.extend(_internal_type_areas(sources))
    areas.extend(_duplicate_function_areas(sources))
    findings = [_finish(area, sources) for area in _merge_areas(areas)]
    findings.sort(key=lambda item: (
        -item["score"], item["id"],
    ))
    ids = [item["id"] for item in findings]
    if len(ids) != len(set(ids)):
        raise ValueError("detectors produced duplicate stable finding IDs")
    return {
        "format_version": FORMAT_VERSION,
        "score_meaning": (
            "detector strength only; not architectural value, deletable lines, "
            "or review priority"
        ),
        "scoring_rule_digest": RULES_DIGEST,
        "source_digest": digest.hexdigest(),
        "component_caps": COMPONENT_CAPS,
        "paths": [source.path for source in sources],
        "findings": findings,
    }


def render_json(report: dict) -> str:
    return json.dumps(report, indent=2) + "\n"


def render_text(report: dict) -> str:
    lines = [
        f"x2c source bloat audit v{report['format_version']}",
        "scores are detector strength, not architectural value or priority",
        f"rules {report['scoring_rule_digest']}",
        f"source {report['source_digest']}",
        f"{len(report['findings'])} findings",
        "",
    ]
    for rank, finding in enumerate(report["findings"], 1):
        locations = ", ".join(
            f"{entry['path']}:" + ",".join(
                str(start) if start == end else f"{start}-{end}"
                for start, end in entry["ranges"]
            )
            for entry in finding["paths"]
        )
        components = ", ".join(
            f"{name}={value}" for name, value in finding["components"].items()
            if value
        )
        lines.extend([
            f"{rank:3}. {finding['score']:3} {finding['id']} {locations}",
            f"     {components or 'no scored components'}",
            f"     {', '.join(finding['declarations'])}",
        ])
        lines.extend(f"     - {item}" for item in finding["evidence"])
    return "\n".join(lines).rstrip() + "\n"


def compare(report: dict, baseline: dict) -> dict:
    if baseline.get("format_version") != FORMAT_VERSION:
        raise ValueError("baseline format version does not match")
    if baseline.get("scoring_rule_digest") != RULES_DIGEST:
        raise ValueError("baseline scoring rules do not match")
    old = {item["id"]: item for item in baseline.get("findings", [])}
    new = {item["id"]: item for item in report["findings"]}
    return {
        "current_score": sum(item["score"] for item in report["findings"]),
        "baseline_score": sum(item["score"] for item in old.values()),
        "added": [new[key] for key in sorted(new.keys() - old.keys())],
        "removed": [old[key] for key in sorted(old.keys() - new.keys())],
        "changed": [
            {"id": key, "before": old[key], "after": new[key]}
            for key in sorted(old.keys() & new.keys())
            if old[key] != new[key]
        ],
    }


def render_compare(result: dict) -> str:
    lines = [
        f"current score: {result['current_score']}",
        f"baseline score: {result['baseline_score']}",
        f"added: {len(result['added'])}",
        f"removed: {len(result['removed'])}",
        f"changed: {len(result['changed'])}",
    ]
    for name in ("added", "removed"):
        lines.extend(f"  {name} {item['id']} ({item['score']})"
                     for item in result[name])
    lines.extend(
        f"  changed {item['id']} "
        f"({item['before']['score']} -> {item['after']['score']})"
        for item in result["changed"]
    )
    return "\n".join(lines) + "\n"


def _arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths", nargs="*", help="repository-relative .x files or directories"
    )
    parser.add_argument(
        "--json", action="store_true", help="write deterministic JSON"
    )
    parser.add_argument(
        "--compare", metavar="BASELINE.json",
        help="compare with a JSON report",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _arguments(sys.argv[1:] if argv is None else argv)
    root = pathlib.Path(__file__).resolve().parent.parent
    try:
        report = analyze(root, args.paths)
        if args.compare:
            baseline_path = pathlib.Path(args.compare)
            baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
            result = compare(report, baseline)
            sys.stdout.write(json.dumps(result, sort_keys=True, indent=2) + "\n"
                             if args.json else render_compare(result))
        else:
            sys.stdout.write(render_json(report) if args.json else render_text(report))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"audit-source-bloat: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
