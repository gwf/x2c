"""Measure the replies agents send Gary for retrospective harness metrics.

`tools/harness-metrics.py` keeps the historical 100-word measure so results
remain comparable with the 2026-08-05 baseline. This measurement is not a
writing target.

Fenced and inline code are dropped before measuring. A snippet or a handoff
prompt Gary asked for is not a wall of text, and penalizing it by length
would only lead agents to paraphrase code in prose.
"""

from __future__ import annotations

import re

# Historical reporting threshold. Do not present it to an agent as a target.
WORD_LIMIT = 100

FURNITURE = (
    ("a heading", re.compile(r"^\s{0,3}#{1,6}\s", re.M)),
    ("a bullet list", re.compile(r"^\s*[-*+]\s+\S", re.M)),
    ("a numbered list", re.compile(r"^\s*\d+[.)]\s+\S", re.M)),
    ("a table", re.compile(r"^\s*\|.*\|\s*$", re.M)),
    ("bold text", re.compile(r"\*\*\S")),
)


def prose(text: str) -> str:
    """Drop code Gary asked for; only the prose around it is the reply."""
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    return re.sub(r"`[^`]*`", " code ", text)


def measure(reply: str) -> tuple[int, list[str]]:
    """Prose word count and the names of any markdown furniture present."""
    body = prose(reply)
    return len(body.split()), [n for n, p in FURNITURE if p.search(body)]


def text_of(record: dict) -> str | None:
    """The assistant text in one transcript record, or None if it is not one.

    A record carrying a tool call is not a reply to Gary, so it reads as an
    empty string rather than None: it ends any reply that preceded it.
    """
    if record.get("type") != "assistant":
        return None
    content = (record.get("message") or {}).get("content")
    if not isinstance(content, list):
        return None
    if any(p.get("type") == "tool_use" for p in content if isinstance(p, dict)):
        return ""
    parts = [p.get("text", "") for p in content
             if isinstance(p, dict) and p.get("type") == "text"]
    return "\n".join(parts).strip()
