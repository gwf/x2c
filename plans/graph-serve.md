> Status: active
> Implement graph serve as a normal delivered capability. The separate
> provenance-lifetime investigation stays unpublished for user review.

# Serve reusable project analysis

## Design and scope

Add `x2c graph serve SNAPSHOT`: one foreground process loads one immutable
snapshot, builds entity/binding/relationship indexes, and answers ordered
newline-delimited JSON queries on stdio. Preserve the one-shot query schema
and response values. Report readiness on stderr. Invalid queries return JSON
errors without terminating the session. EOF closes the server.

The shared engine receives a session by value. A request owns its reachability
cache, Match plan, parsed JSON, results, and canonical allocations in an
isolated Context. The session builds all retained indexes before request
contexts open. No live compiler, automatic reload, background daemon, network
listener, or new semantic resolver is introduced.

Review confirmed the existing query evaluator needs only request-local mutable
state plus read-only indexes. Preserve one-shot lazy indexing. The server pays
relationship indexing at startup to keep all durable allocations in its own
lifetime. This trades startup and retained memory for repeated-query latency.

## Acceptance and delivery

Verify every query operation against one-shot output, recovery after invalid
JSON and query patterns, repeated distinct reachability queries, snapshot
replacement while serving, EOF, and an unterminated final line. Measure
startup, warm queries, and resident memory across hundreds of requests using
the same saved snapshot and queries for both execution modes. No recurring
memory threshold or new gate is added. Review the authored diff, then run the
existing publication gate and publish normally.

After implementation, another agent uses graph serve to investigate whether
compiler source-provenance data can be released earlier. Its queries, probes,
and report remain scratch artifacts. It must distinguish static reachability
from execution order and alias effects. No proposed production changes from
that experiment are implemented or published without later direction.
