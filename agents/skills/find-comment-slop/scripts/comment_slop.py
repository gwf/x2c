#!/usr/bin/env python3
"""Find likely removable comments in hand-authored x2c source."""

from __future__ import annotations

import argparse
import bisect
import collections
import dataclasses
import json
import re
import subprocess
import sys
from pathlib import Path


VERBS = {
    "add", "append", "apply", "build", "check", "close", "collect",
    "compare", "compute", "convert", "copy", "create", "decode",
    "decide", "emit", "encode", "expect", "find", "format", "generate",
    "get", "handle", "initialize", "insert", "load", "lower", "make",
    "normalize", "open", "parse", "print", "process", "read", "remove",
    "resolve", "return", "save", "scan", "set", "store", "test",
    "tokenize", "transform", "update", "validate", "write",
}

REASON_WORDS = {
    "because", "cannot", "consequence", "except", "invariant", "must",
    "never", "only", "otherwise", "owner", "owns", "preserve", "requires",
    "so", "unless", "until", "why", "without",
}

STOP_WORDS = {
    "a", "an", "and", "as", "at", "by", "for", "from", "in", "into",
    "is", "it", "of", "on", "one", "or", "the", "this", "to", "when",
    "with",
}

HISTORY_RE = re.compile(
    r"\b(?:TODO|FIXME|BUG|NB:|moved verbatim|recently|formerly|used to|"
    r"old logic|added (?:this|the)|for now)\b",
    re.IGNORECASE,
)

@dataclasses.dataclass
class Comment:
    path: str
    kind: str
    start: int
    end: int
    start_offset: int
    end_offset: int
    raw: str
    text: str

    @property
    def line_count(self) -> int:
        return self.end - self.start + 1

    @property
    def normalized(self) -> str:
        return normalize_text(self.text)


@dataclasses.dataclass
class Candidate:
    path: str
    start: int
    end: int
    severity: str
    removable_lines: int
    reasons: list[str]
    excerpt: str


@dataclasses.dataclass
class FileResult:
    path: str
    high_lines: int
    medium_lines: int
    high_count: int
    medium_count: int
    comment_lines: int
    candidates: list[Candidate]


def normalize_text(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def word_tokens(text: str) -> list[str]:
    expanded = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", text)
    return [word.lower() for word in re.findall(r"[A-Za-z0-9]+", expanded)]


def content_tokens(text: str) -> set[str]:
    return {
        word for word in word_tokens(text)
        if len(word) > 1 and word not in STOP_WORDS
    }


def clean_comment(raw: str, kind: str) -> str:
    if kind == "line":
        cleaned = []
        for line in raw.splitlines():
            cleaned.append(re.sub(r"^\s*//\s?", "", line).rstrip())
        return "\n".join(cleaned).strip()

    body = raw
    body = re.sub(r"^\s*/\*\*?", "", body, count=1)
    body = re.sub(r"\*/\s*$", "", body, count=1)
    cleaned = []
    for line in body.splitlines():
        cleaned.append(re.sub(r"^\s*\*?\s?", "", line).rstrip())
    return "\n".join(cleaned).strip()


def _line_starts(text: str) -> list[int]:
    starts = [0]
    starts.extend(match.end() for match in re.finditer(r"\n", text))
    return starts


def _line_number(starts: list[int], offset: int) -> int:
    return bisect.bisect_right(starts, offset)


def extract_comments(text: str, path: str) -> list[Comment]:
    """Extract C-style comments while ignoring quoted strings and chars."""
    starts = _line_starts(text)
    comments: list[Comment] = []
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        if char in {'"', "'"}:
            quote = char
            index += 1
            while index < length:
                if text[index] == "\\":
                    index += 2
                    continue
                if text[index] == quote:
                    index += 1
                    break
                index += 1
            continue
        if text.startswith("//", index):
            begin = index
            finish = text.find("\n", index)
            if finish < 0:
                finish = length
            raw = text[begin:finish]
            comments.append(Comment(
                path=path,
                kind="line",
                start=_line_number(starts, begin),
                end=_line_number(starts, max(begin, finish - 1)),
                start_offset=begin,
                end_offset=finish,
                raw=raw,
                text=clean_comment(raw, "line"),
            ))
            index = finish
            continue
        if text.startswith("/*", index):
            begin = index
            close = text.find("*/", index + 2)
            finish = length if close < 0 else close + 2
            raw = text[begin:finish]
            kind = "doc" if text.startswith("/**", index) else "block"
            comments.append(Comment(
                path=path,
                kind=kind,
                start=_line_number(starts, begin),
                end=_line_number(starts, max(begin, finish - 1)),
                start_offset=begin,
                end_offset=finish,
                raw=raw,
                text=clean_comment(raw, kind),
            ))
            index = finish
            continue
        index += 1
    return merge_line_comments(comments, text)


def merge_line_comments(comments: list[Comment], source: str) -> list[Comment]:
    merged: list[Comment] = []
    for comment in comments:
        if (
            merged
            and comment.kind == "line"
            and merged[-1].kind == "line"
            and comment.start == merged[-1].end + 1
            and not source[merged[-1].end_offset:comment.start_offset].strip()
        ):
            previous = merged[-1]
            raw = source[previous.start_offset:comment.end_offset]
            merged[-1] = Comment(
                path=comment.path,
                kind="line",
                start=previous.start,
                end=comment.end,
                start_offset=previous.start_offset,
                end_offset=comment.end_offset,
                raw=raw,
                text=clean_comment(raw, "line"),
            )
        else:
            merged.append(comment)
    return merged


def source_after(comment: Comment, source: str, line_count: int = 8) -> tuple[str, int]:
    lines = source.splitlines()
    index = comment.end
    while index < len(lines) and not lines[index].strip():
        index += 1
    return "\n".join(lines[index:index + line_count]), index + 1


def declaration_name(after: str) -> str | None:
    markers = [position for position in (after.find("{"), after.find("=>"))
               if position >= 0]
    if not markers:
        return None
    prefix = after[:min(markers)]
    if ";" in prefix:
        return None
    matches = re.findall(
        r"([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)\s*\(",
        prefix,
    )
    if not matches:
        return None
    excluded = {"if", "for", "while", "switch", "return", "sizeof", "match"}
    for name in reversed(matches):
        if name not in excluded:
            return name
    return None


def paragraph_parts(text: str) -> list[str]:
    return [part.strip() for part in re.split(r"\n[ \t]*\n", text) if part.strip()]


def _add(
    findings: dict[int, Candidate],
    key: int,
    comment: Comment,
    severity: str,
    reason: str,
    removable_lines: int | None = None,
) -> None:
    lines = removable_lines or comment.line_count
    excerpt = normalize_text(comment.text)
    if len(excerpt) > 150:
        excerpt = excerpt[:147] + "..."
    existing = findings.get(key)
    if existing is None:
        findings[key] = Candidate(
            path=comment.path,
            start=comment.start,
            end=comment.end,
            severity=severity,
            removable_lines=min(lines, comment.line_count),
            reasons=[reason],
            excerpt=excerpt,
        )
        return
    if reason not in existing.reasons:
        existing.reasons.append(reason)
    if severity == "high":
        existing.severity = "high"
    existing.removable_lines = min(
        comment.line_count,
        max(existing.removable_lines, lines),
    )


def _manifest_tiers(root: Path) -> dict[str, str]:
    manifest = root / "docs/library-manifest.txt"
    if not manifest.exists():
        return {}
    tiers = {}
    for raw in manifest.read_text(encoding="ascii").splitlines():
        if not raw or raw.startswith("#"):
            continue
        fields = raw.split("|", 2)
        if len(fields) >= 2:
            tiers[fields[0]] = fields[1]
    return tiers


def classify_file(path: str, source: str, tiers: dict[str, str]) -> FileResult:
    comments = extract_comments(source, path)
    findings: dict[int, Candidate] = {}

    for index, comment in enumerate(comments):
        text = comment.normalized
        words = word_tokens(text)
        after, next_line = source_after(comment, source)
        name = declaration_name(after)
        next_code = next((line.strip() for line in after.splitlines() if line.strip()), "")

        if HISTORY_RE.search(text):
            _add(findings, index, comment, "high", "history or unfinished-work narration")

        if re.search(r"prevent null pointer dereference|check (?:for )?null", text, re.I):
            _add(findings, index, comment, "high", "narrates an obvious null guard")

        letters = re.sub(r"[^A-Za-z]", "", text)
        decorated = bool(re.search(r"[-=]{4,}", text))
        all_caps = (
            len(letters) >= 4
            and letters.upper() == letters
            and len(words) <= 8
        )
        if comment.kind == "line" and (decorated or all_caps):
            _add(findings, index, comment, "high", "decorative or all-capitals section label")
        elif len(words) <= 4 and text.lower() in {
            "private helpers", "public interface", "public entry points",
            "helper functions", "utility functions",
        }:
            _add(findings, index, comment, "medium", "catalog-style section label")

        if comment.kind != "doc" and name and words:
            function_tokens = content_tokens(name.replace(".", "_"))
            prose_tokens = content_tokens(text)
            first = words[0]
            shared = function_tokens & prose_tokens
            has_reason = bool(REASON_WORDS & set(words))
            matching_verb = first in VERBS and first in function_tokens
            if not has_reason and len(words) <= 12 and (
                matching_verb
                or len(shared) >= min(2, len(function_tokens))
            ):
                _add(findings, index, comment, "high", "restates the following function name")

        if comment.kind != "doc" and not name and len(words) <= 12 and next_code:
            prose_tokens = content_tokens(text)
            code_tokens = content_tokens(next_code)
            overlap = prose_tokens & code_tokens
            has_reason = bool(REASON_WORDS & set(words))
            if (
                not has_reason
                and len(prose_tokens) >= 2
                and len(overlap) / len(prose_tokens) >= 0.75
            ):
                _add(findings, index, comment, "high", "translates the following statement")

        if comment.kind == "block" and comment.start <= 20:
            verb_count = sum(1 for word in words if word in VERBS)
            if verb_count >= 5 or len(re.findall(r"`[^`]+`", text)) >= 5:
                _add(
                    findings, index, comment, "medium",
                    "module header inventories implementation",
                )

        if comment.kind == "doc":
            if path.startswith("src/"):
                _add(
                    findings, index, comment, "high",
                    "generated-reference delimiter in compiler source",
                )
            tier = tiers.get(path)
            if tier in {"contract", "internal"}:
                _add(findings, index, comment, "high", f"doc comment in {tier} library module")
            if re.search(r"@param|@return|\bParameters:|\bReturns:", text):
                _add(findings, index, comment, "high", "forbidden parameter or return boilerplate")
            if re.match(r"static\b", next_code):
                _add(
                    findings, index, comment, "high",
                    "public doc comment on a private static helper",
                )
            if next_line > comment.end + 1:
                _add(findings, index, comment, "high", "doc comment detached from its declaration")
        if re.search(r"\b(?:important|obvious|obviously|robust|simply|just)\b", text, re.I):
            _add(findings, index, comment, "medium", "vague or persuasive prose")

        if index + 1 < len(comments):
            following = comments[index + 1]
            between = source[comment.end_offset:following.start_offset]
            if comment.kind == "doc" and following.kind == "doc" and not between.strip():
                _add(
                    findings, index, comment, "high",
                    "stacked doc comment is detached from a definition",
                )

    paragraph_owners: dict[str, list[tuple[int, int]]] = collections.defaultdict(list)
    for index, comment in enumerate(comments):
        parts = paragraph_parts(comment.text)
        start_at = 1 if comment.kind == "doc" else 0
        for part in parts[start_at:]:
            normalized = normalize_text(part).lower()
            if len(word_tokens(normalized)) >= 6:
                paragraph_owners[normalized].append(
                    (index, part.count("\n") + 1)
                )
    for owners in paragraph_owners.values():
        if len(owners) < 2:
            continue
        for index, lines in owners:
            _add(
                findings,
                index,
                comments[index],
                "medium",
                "repeats prose elsewhere in the file",
                lines,
            )

    candidates = sorted(
        findings.values(),
        key=lambda item: (
            item.severity != "high",
            -item.removable_lines,
            item.start,
        ),
    )
    high = [item for item in candidates if item.severity == "high"]
    medium = [item for item in candidates if item.severity == "medium"]
    return FileResult(
        path=path,
        high_lines=sum(item.removable_lines for item in high),
        medium_lines=sum(item.removable_lines for item in medium),
        high_count=len(high),
        medium_count=len(medium),
        comment_lines=sum(comment.line_count for comment in comments),
        candidates=candidates,
    )


def expand_paths(arguments: list[str], root: Path) -> list[str]:
    requested = arguments or ["src", "lib"]
    found: set[str] = set()
    for raw in requested:
        path = root / raw
        if path.is_dir():
            for child in path.rglob("*.x"):
                found.add(child.relative_to(root).as_posix())
        elif path.is_file() and path.suffix == ".x":
            found.add(path.relative_to(root).as_posix())
        elif raw.endswith(".x"):
            found.add(raw)
    found.discard("lib/x2c.x")
    return sorted(found)


def read_revision(path: str, revision: str | None, root: Path) -> str:
    if revision:
        return subprocess.check_output(
            ["git", "show", f"{revision}:{path}"],
            cwd=root,
            text=True,
        )
    return (root / path).read_text(encoding="ascii")


def rank_results(results: list[FileResult], rank: str = "violations") -> list[FileResult]:
    if rank == "bloat":
        return sorted(
            results,
            key=lambda item: (
                -item.medium_lines,
                -item.medium_count,
                -item.high_lines,
                item.path,
            ),
        )
    return sorted(
        results,
        key=lambda item: (
            -item.high_lines,
            -(item.high_lines + item.medium_lines),
            -item.high_count,
            item.path,
        ),
    )


def result_json(result: FileResult) -> dict[str, object]:
    return {
        "path": result.path,
        "high_confidence_lines": result.high_lines,
        "review_lines": result.medium_lines,
        "high_confidence_candidates": result.high_count,
        "review_candidates": result.medium_count,
        "comment_lines": result.comment_lines,
        "candidates": [dataclasses.asdict(item) for item in result.candidates],
    }


def print_results(results: list[FileResult], limit: int, details: bool) -> None:
    shown = results[:limit] if limit else results
    print("violation-lines  review-lines  violations  reviews  comments  file")
    for result in shown:
        print(
            f"{result.high_lines:15d}  {result.medium_lines:12d}  "
            f"{result.high_count:10d}  {result.medium_count:7d}  "
            f"{result.comment_lines:8d}  {result.path}"
        )
        if details:
            for candidate in result.candidates:
                reasons = "; ".join(candidate.reasons)
                print(
                    f"      {candidate.severity:6s} {candidate.start:4d}-"
                    f"{candidate.end:<4d} {candidate.removable_lines:3d}  {reasons}"
                )
                print(f"             {candidate.excerpt}")


def _revision_paths(revision: str, requested: list[str], root: Path) -> list[str]:
    names = subprocess.check_output(
        ["git", "ls-tree", "-r", "--name-only", revision, "--", *requested],
        cwd=root,
        text=True,
    ).splitlines()
    return sorted(
        name for name in names
        if name.endswith(".x") and name != "lib/x2c.x"
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help=".x files or directories")
    parser.add_argument("--rev", help="scan files from a Git revision")
    parser.add_argument("--limit", type=int, default=20, help="files to show; 0 shows all")
    parser.add_argument("--details", action="store_true", help="show each candidate")
    parser.add_argument("--json", action="store_true", help="emit JSON")
    parser.add_argument(
        "--rank",
        choices=("violations", "bloat"),
        default="violations",
        help="rank exact violations or prose needing bloat review",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    root = Path.cwd()
    tiers = _manifest_tiers(root)
    paths = (
        _revision_paths(args.rev, args.paths or ["src", "lib"], root)
        if args.rev
        else expand_paths(args.paths, root)
    )
    results = []
    for path in paths:
        try:
            source = read_revision(path, args.rev, root)
        except (FileNotFoundError, subprocess.CalledProcessError, UnicodeError) as error:
            print(f"comment_slop.py: {path}: {error}", file=sys.stderr)
            return 2
        results.append(classify_file(path, source, tiers))
    ranked = rank_results(results, args.rank)
    if args.json:
        print(json.dumps([result_json(result) for result in ranked], indent=2))
    else:
        print_results(ranked, args.limit, args.details)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
