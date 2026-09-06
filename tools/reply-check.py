#!/usr/bin/env python3
"""Stop hook: block only an actual wall of text before Gary has to read it.

The root `AGENTS.md` Communication section asks for judgment at the moment of
temptation, which `plans/harness-baseline-2026-08-05.md` measured as the
weakest instrument the harness has: a paragraph asking agents to justify a
repeated gate left the behavior slightly worse, while a renamed command moved
it from 82% to 9%. This is the command form of that section.

The threshold is deliberately well above a normal technical explanation. It
blocks once, and a second stop is always allowed, so a reply whose length is
genuinely earned still lands. Wired as a `Stop` hook in
`.claude/settings.json`; it touches nothing in the tree and fails open on
anything unexpected.

The event carries the reply as `last_assistant_message`. The transcript is
not flushed yet when the hook runs, so reading it there finds the previous
turn; it is only a fallback for an event that omits the field.

    echo '{"last_assistant_message":"...","stop_hook_active":false}' |
        tools/reply-check.py
"""

from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from x2c_reply import final_reply, measure  # noqa: E402


WALL_LIMIT = 250


def complaint(reply: str) -> str:
    words, _ = measure(reply)
    if words <= WALL_LIMIT:
        return ""
    return (
        f"That draft runs {words} words of prose and has become a session "
        "recap. Rewrite it as a direct, self-contained answer. Keep the "
        "cause, consequence, and next action needed to understand the "
        "result; remove chronology, repeated evidence, process narration, "
        "and Git bookkeeping. Do not compress the answer into fragments or "
        "mention this warning."
    )


def main() -> int:
    try:
        event = json.load(sys.stdin)
        if event.get("stop_hook_active"):
            return 0
        reply = event.get("last_assistant_message")
        if reply is None:
            reply = final_reply(event["transcript_path"])
        reason = complaint(reply)
    except Exception:  # a broken hook must never wedge a session
        return 0
    if reason:
        json.dump({"decision": "block", "reason": reason}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
