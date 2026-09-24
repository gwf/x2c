# Evidence record

Each external run contains deterministic `inventory.json`, `selection.json`,
`attempts.jsonl`, `commands.txt`, and a human-reviewed `report.md`.

For every selected region, append one JSON object to `attempts.jsonl` after
review with: `candidate_id`, `source_digest`, `outcome`, `reason`, and any
`commits` or `sessions`. The allowed outcomes are `candidate`, `empty`, and
`refuted`. Keep the explanation concrete enough to avoid repeating the same
search. The discovery script regards every selection as attempted even before
the review record is appended, so an interrupted run does not loop forever.

The tracked ledger uses this table:

| Candidate | Location | Machinery | Claimed purpose | Production consumers | Overreach evidence | Removal hypothesis | Strongest keep case | Provenance | Status / confidence | Next proof |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

Candidate IDs are stable `path:symbol` identities. A region digest records the
reviewed body. Lines are current evidence and may move; refresh them whenever a
row is reviewed.

Confidence describes the evidence for the disposition, not the desirability or
safety of deletion. Never infer that no callers means no contract.
