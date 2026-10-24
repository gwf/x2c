# Module blocks: one source split across a directory

> Status: done - delivered 2026-10-11, recorded by `0ff8816e`, on dev
> before `6529e868`. Discovery and script boundaries were repaired by
> `28fc8c97`. This replaces the separate-unit design researched on
> `codex/module-m1-current-dev`, which remains historical reference.

## Follow-ups recorded on 2026-10-12

The [remediation plan](review-remediation-2026-10-11.md#module-follow-ups)
owns included-member effect replay locations and normalized companion-path
containment. Commit `9db47909` fixed entry-file columns and context after the
module block's closing brace. It did not repair exported member effects that
replay with the entry filename and cleared source markers. The current source
retains that mapping path; the historical reproduction was not rerun at
`2b5ee957`. Recheck the included-member replay case before implementation.

## Requirement

Split a large source file into a directory of files that share one private
namespace, with no cost to units that do not use it. The author decides the
split; the compiler produces exactly what the one large file would have
produced.

## Decision

A module is one translation unit assembled from an entry file and the member
files its `module` block names. The block is textual inclusion at its
position: the compiler reads the entry, replaces the block with the members'
text in order, and translates the result as one unit. `static` is the
private namespace, as it is for any single file. Nothing else is new: no
visibility keyword, no ownership discovery, no native-name scheme, no
interface change, no build expansion.

```x2c
/* calculations.x */
#include "x2c.x"

module {
  "calculations/implementation.x",
}

int main(void) { return helper(40) + counter; }
```

```x2c
/* calculations/implementation.x */
static int counter = 0;
static int helper(int value) { return value + counter; }
```

## Contract

- `module {` at file scope, followed by comma-separated string paths, an
  optional trailing comma, and `}` with no semicolon. One block per file.
  Member paths are relative to the entry and must lie under the entry's
  companion directory, `NAME/` for `NAME.x`; anything else is a diagnostic
  at the block.
- A member is spliced where the block stands. Declarations before the block
  are visible to every member; a member's statics are visible to later
  members and to the entry after the block. Function declarations are
  collected across the whole unit, so calls to later-defined functions need
  no explicit prototype. Other declarations retain ordinary placement rules.
  A member may hold its own block, spliced in turn; the namespace stays flat.
- Members are not translation units. The build never lists them; the entry's
  C and header carry everything. The entry's depfile and collection entry
  depend on every member's content, so editing a member retranslates the
  entry. A member translated on its own is an ordinary file, as any `.x` is.
- Diagnostics, `--dump-*` positions, the editor, the REPL, lint, and the graph
  tool report member positions in the member file, through the line-marker
  mechanism the host-preprocessor path already uses (`Compiler.line_markers`,
  `token_source`).
- An unrelated unit that includes the entry collects the whole module's
  public declarations, since collection reads the spliced text. An unrelated
  unit that includes a member directly collects a fragment; the same
  duplicate-definition diagnostics that exist today apply, and no new check is
  added.
- Units without a block pay nothing: no filesystem probing, no extra
  dependency rows, no change in instruction counts.

## Implementation owner

Expansion happens where a unit's source text is established, before the
collection walk splits it at includes and before the full parse: one
operation that reads a `.x` text, finds a file-scope `module` block, reads
each member (recursively), and returns the spliced text with line markers, the
member paths, and their content hashes. Both the frontend's unit text and the
collector's cold walk of an included entry go through it, so an entry behaves
the same when translated and when included. `#include` inside a member
resolves relative to the member's own directory, as the splice preserves the
member's path in the marker. The block's recognition is lexical, at file scope
only; `module` elsewhere stays an ordinary identifier.

## Evidence

Fixtures in the harness, run by the gate:

1. The split above, running and printing its result; the generated C equals
   the one-file version apart from line markers.
2. A member declaring a static used by a later member and by the entry.
3. A nested entry: a member with its own block.
4. A member path outside the companion directory: diagnostic at the block.
5. A diagnostic inside a member reporting the member's file and line.
6. An unrelated unit including the entry and using a public function from a
   member.
7. The dump fixtures (`--dump-ast`) for a module showing member positions.

Measurements, converged compilers, equal-length paths, median of 3: the empty
unit and a 1000-function unit must not move; a module of four members against
the same code in one file must be within noise; the depfile of a unit without a
block is unchanged. `make verify`, `make proof-cold-collection`, and the
header-cache and symbol-snapshot probes pass.

## Review

The design adds one read-time operation and one lexical form and reuses every
downstream mechanism unchanged. It gives up per-member compilation and
per-member privacy, which the separate-unit design paid 1,774 kernel lines, a
doubled per-unit cost, and an interface format bump to provide. If per-member
compilation is wanted later, the block already names the members.

## Result, 2026-10-11

`Compiler.module_source` in src/collect.x splices members at read time and
returns the text, the marker rows, and member content hashes; the frontend's
unit text, the collector's cold walk (`_walk_apart`), and the project meta
scan reach it. A file without a block costs one substring search. Member
positions reach diagnostics, origins, `--source-map`, and the editor through
`token_source` and a new `Compiler.text_source`; member hashes join the
collection entry, the `.xi`, and the depfile. A member's quoted include of a
file beside it is rewritten to the entry-relative spelling while splicing, so
collection, parsing, and the generated `#include` agree. The cpp-symbol modes
reject a module unit as they reject indented and script units. Source
+320/-21; eight fixtures (the plan's seven and `module-block-meta`); book
section "Module blocks". Measurements against dev: empty unit 1,192 M both;
1,000-function unit 2,930 M -> 2,928 M; a four-member module within noise of
the same code in one file; depfile of a unit without a block unchanged.
Generated C byte-identical for every fixture and the compiler's sources. Open:
compile-time effects replayed from a member report the entry file and the
spliced line; the companion check is textual and rejects `NAME/../NAME/x.x`.
