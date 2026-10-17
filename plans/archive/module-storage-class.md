> Status: done; archived 2026-10-16 after delivery in #196 and #197.
> Module adoption and layout work landed through #273 (`fab576c2`).
> The design and limits below are historical, not newly verified defects.
> Current member paths are relative to the entry directory and may name
> siblings or parents. Private prefixes include the encoded spelling length.
> The language reference and `src/collect/splice.x` own the current contract.

> Historical delivery record: landed on `dev` in #196 (`bd63bc6f`) and its second
> review round in #197 (`ef772117`). Stages 0 and 1 agree. Known limits:
> a private class's repr heading shows the prefixed name
> (`second__Node { ... }`), because `_class_write_fields` in `src/builtins.x`
> has no compiler access, and a standalone `static struct Foo {...};` tag is
> not prefixed, only tags under `static typedef` or `static class`. Review
> fixes 2026-10-14: a block-scope typedef or tag shadows a file-private
> type; the names the compiler derives from a prefixed spelling
> (`Node_new`, `Var_node`) are recognized from the unit's recorded prefixed
> declarations (`Sym.prefixed`, written by `Compiler.declared_spelling`,
> with replayed collected declarations recorded as final) instead of a
> substring test on source names; the shadow diagnostic covers typedefs and
> tags in either order within each C namespace; a free name in a macro body
> binds at the expansion site (`_file_key` skips templates); enumerators of
> a `static typedef enum` are file-private (a plain `static enum`'s stay
> unit-wide); the file prefix ends in `___` so a package
> entry's statics never share a spelling with `pkg__` public names;
> `--dump-definitions` displays the source name; and a file-scope typedef
> named `module` keeps the word an identifier. Remaining limits: a type name
> in a macro body is spelled where the macro is defined (template type
> names are raw strings by design); diagnostics and editor hover print the
> prefixed key, as package mode does; `Sym.prefixed` is not transaction
> undone, which only matters for a rolled-back declaration whose spelling a
> later source name repeats.
> The step 2 worker also fixed an existing defect: a `static class`
> in a member got different Var tags for boxing and its descriptor
> (`_canonical_file` in `src/protocol.x` now maps a member to its unit).
> Post-merge review 2026-10-14: a later declaration of a static without
> `static` (a definition after a `static` prototype) and a block-scope
> `extern` or function prototype now take the static's key, as C links
> them, where both failed to link; trailing `_` of a path's spelling are
> dropped before `___`, so `a.x` and `a-.x` report one prefix.
> Supersedes the paused `codex/nested-modules-spike` design on the shipped
> text-splicing base; that spike stays a saved experiment.

# `module` storage class and file-private `static` in module units

## Result

A module unit is an entry file with a file-scope `module { ... }` block
([module blocks](../../docs/src/reference/language.md#module-blocks)). Its
members are spliced into one text and one translation unit. Today every
file-scope `static` in that unit is visible to every member, so a module
has no file-private names. This change gives it two storage classes:

| Spelling | Visibility in source | Emitted C |
| --- | --- | --- |
| `module T name` | every file of the module unit, by the short name; never exported to the `.xi` | `static T name` |
| `static T name` | the declaring file only | `static T <file>__name` |

`module` is a contextual word at file scope. `module int depth;`,
`module void advance(void) {...}`, and `module typedef struct Node {...}
Node;` are declarations. `module {` still opens the member block, and
`module` elsewhere stays an ordinary identifier, so `String module` in
`src/build.x` keeps compiling.

`static` keeps its C meaning: visible in this file only. That holds for
objects, functions, `static typedef`, and the `struct`, `union`, and `enum`
tags such a typedef declares. Two members may each declare
`static int counter` or `static typedef struct Node {...} Node`, and each
file sees only its own. A `module` function may take or return a file-private
type; other files can call it without being able to spell the type, as in
C with an opaque handle.

The prefix is the member's path under the entry's companion directory
with the extension dropped and every non-identifier character mapped to
`_`, then `___`. `parser/statements/loops.x` under entry `parser.x` gives
`statements_loops___advance`. The entry's own statics use the entry stem,
`parser___advance`, so the rule is one rule for every file of the unit. A
package prefix ends in `__`, so the two never coincide.
Generated names are compiler details; source never spells them.

Outside a module unit nothing changes. A file without a block, including a
member translated on its own, keeps unprefixed statics, and `module` there
means `static`.

Compile-time declarations are outside this change. `static macro`,
`static $(`, `static protocol`, and `meta` functions keep their current
unit-wide behavior; they are not C identifiers.

## Settled choices

- **Keys, not emission renames.** The symbol table is keyed by spelling per
  unit, so two members' `static int foo` must have different keys, and
  typedef names and aggregate tags are emitted from raw strings that
  `Compiler.emitted_binding_name` never sees (`src/parse.x:1474-1481`,
  `src/symbols.x:753-757`). Package mode already solves exactly this:
  `_package_declared_key` (`src/symbols.x:575-592`) respells file-scope
  non-static keys to `pkg__name` at declaration, and
  `_package_type_reference` (`src/parse.x:1487-1497`) respells a bare type
  reference when the bare key misses and the prefixed key hits. File-private
  statics use the same two operations with the file prefix on static keys.
  The `(emitted BINDING)` fact route is rejected for this reason.
- **`module` lowers to `static` in the AST.** The parser consumes the word
  and parses the declaration with its storage set to `static`, under a flag
  that tells key respelling to leave the key bare. Every existing static
  consumer, `_track_static`, `record_declaration_visibility`,
  `file_statics()`, `_select_public`, and `_without_static`, then applies
  unchanged. The emitter needs no `<module>` mapping.
- **Var tags stay the short name.** `_seed_var_tag` and `_descriptor` derive
  the tag from the type spelling (`src/symbols.x:313-331`,
  `src/protocol.x:2701-2711`). Tag registration strips the file prefix
  before deriving the tag, so `static typedef struct Node` adopted as a
  class keeps tag `node`. Two members adopting a class under the same short
  name would register one tag twice; that is diagnosed, since the runtime
  would silently merge them.
- **Prefix collisions are diagnosed at splice.** `a_b.x` and `a/b.x` map to
  the same prefix. `_member` in `src/collect.x` already records each member;
  a second member with an already recorded prefix is a driver error at the
  block, like the existing member-path errors.
- **A `static` that shadows a `module` name is diagnosed.** `module`
  promises one meaning per name across the unit. Declaring
  `static int depth` in a file when `(depth)` is a module-wide static of the
  unit, or declaring `module int depth` when some file already declared a
  prefixed `depth`, is a parse error at the later declaration. Functions are
  collected across the unit first, so either order is caught for them;
  object order follows splice order.
- **Duplicate `module` definitions need no new diagnostic.** Two members
  defining `module void advance(void)` produce one key and the existing
  redefinition diagnostic.
- **Current file at a declaration or reference** comes from
  `Compiler.token_source` (`src/diagnostics.x:376-383`), which the parser
  already calls per anchored node through `record_origin` when markers
  exist. If measurement shows the extra lookups matter for the compiler's
  own build, a cursor over the sorted marker rows is the routine fix.

## Implementation

One branch, two steps, with a bootstrap refresh between them, because the
compiler's own source uses module blocks (`src/compiler.x:316-327`,
`src/compiler/parsing.x:81-87`, `src/compiler/declarations.x:15-19`) and
its members share statics across files. The shipped bootstrap cannot read
`module` declarations, so the keyword must be refreshed into `bootstrap/`
before `src/` uses it, and `src/` must use it before statics go private.

### Step 1: the `module` storage class

1. `src/parse.x`: in `parse_top_level_mode`, next to `_static_interface_form`,
   recognize `module` followed by a declaration start other than `{`.
   Consume it and parse the form as if `static` were present, with
   `source_private` set as the static path sets it, under a new
   `c.module_declaration` flag for the duration of that declaration.
   `_storage_class` and `_declaration_types` see `<static>`.
2. `src/collect.x` signature collection reuses the same production, so a
   `module` function is collected across the unit like a static one.
3. Book: add the storage class to the module-blocks section and the
   `static` type rule at `language.md:34-41`; grammar at
   `docs/src/reference/syntax/grammar.md:39-46`.
4. Fixture `module-storage-class`: entry plus two members, `module` object,
   function, and typedef used from a later member and from the entry;
   sidecars `c stdout status`, and the `.xi` shows nothing of them
   (`symbols` sidecar).
5. `make bootstrap-refresh` on the branch so the seed consumes `module`.
6. Convert the compiler's cross-member statics to `module`. Enabling step 2
   locally lists them as undefined identifiers; the second explorer's scan
   named `_record_top_level`, `_record_span`, `_check_static_inits`,
   `_end_index`, `_check_unmatched_braces`, `_fact`, `_declaration_path`,
   and `_restore_declaration_bindings` as a start.

### Step 2: file-private `static`

1. `src/collect.x`: compute each spliced file's prefix in `_member` and
   `module_source`, store it with the marker rows (one more field or a
   parallel map keyed by path), and diagnose a repeated prefix
   (`$report.driver.module_prefix`).
2. `src/symbols.x`: generalize `_package_declared_key` into one key
   respelling that applies the package prefix to non-static keys and the
   file prefix to static keys of a module unit, skipping keys declared under
   `c.module_declaration`. Objects, functions, `(typedef name)`, and
   `(struct|union|enum tag)` for a tag declared with a body in that file
   are covered.
3. `src/parse.x`: generalize `_package_type_reference` and the identifier
   lookup so a bare reference tries the current file's prefixed key before
   the bare key. Package mode and module mode compose: a static in a
   package module member gets the file prefix only.
4. Var tags: strip the file prefix in `_seed_var_tag` and `_descriptor`
   when deriving the tag; diagnose a second adoption of the same short name
   (`$report.parse.module_tag`).
5. Shadow diagnostic (`$report.parse.module_shadow`) in `Sym.declare` at
   file scope of a module unit.
6. Fixtures: `module-block-statics` asserts the old rule in its comment and
   body; rewrite it to assert the new rule, with one `static` per member
   under one name and a `module` name shared. Update `module-block`,
   `module-block-member-paths`, `module-block-nested`, `module-block-trivia`,
   `module-block-included` (its `static int scale`), and
   `unittest/probes/run-cli-boundary.sh:1993-2018` to use `module` where
   they cross files. Add `module-block-static-typedef` (two members, same
   `static typedef struct Node`, one adopted class, `c stdout status`) and
   negative fixtures for the prefix collision, the shadow, and the duplicate
   tag.
7. Book: rewrite `language.md:74-78`, which says `static` remains the
   private namespace and nothing else is new, and the member example at
   `:84-103` that reads a member's static from the entry. Update
   `docs/src/internals/implementation-map.md:162-176` owners.
8. Review the completed authored diff for reuse, deleted code, and
   unnecessary checks before publication validation.

## Compatibility

- Any existing module unit whose members share statics stops compiling
  with undefined-identifier errors naming the short name. The fix is to
  spell those `module`. Only `src/` and the fixtures above do this today;
  `lib/`, `commands/`, and `examples/` have no module blocks.
- Generated C for every module unit changes: prefixed static names. Public
  C names, `.xi` contents for public rows, Var tags, and descriptor names
  are unchanged. A promoted static type family needed by a public row
  publishes under its prefixed spelling, as it publishes under its bare
  spelling today.
- `module` as an identifier keeps working everywhere except as the first
  word of a file-scope declaration.

## Validation and delivery

- Focused: `make x2c` plus the module fixtures through
  `unittest/run.sh check --fixture <name>`, and the CLI boundary probe.
- Self-host: after step 2, diff self-translated `src` C against
  `bootstrap/` to see only the expected prefix renames
  (`agents/quick-start.md`).
- Publication: `tools/gate-state.py ensure agent-pr-check`; the bootstrap
  delta is large and expected. Performance checkpoint: the per-reference
  `token_source` call is on the parse path for module units, so run the
  self-build timing from `agents/performance-checkpoints.md` once and keep
  the cursor fix in reserve.
- Delivery as one PR against `dev` with both steps, if the integrated
  bootstrap refresh lands cleanly; otherwise step 1 as its own PR first.

## Plan review

- **Facts trusted.** `Type.is_static` and `_track_static` establish static
  storage; `record_declaration_visibility` establishes privacy;
  `_select_public` establishes export. The design adds no recheck of those.
  Function collection across the unit establishes function keys before
  bodies parse; the shadow diagnostic relies on it rather than re-walking.
- **Reused and deleted.** `_package_declared_key` and
  `_package_type_reference` become the single key respelling for both
  package and file prefixes; no second respelling path is added. The emitter
  and every static consumer are untouched. Nothing is deleted; the spike's
  `module-tree.x` and `module-access.x` are not imported.
- **New mechanism and why.** One prefix per spliced file, recorded at splice
  time, because the key respelling needs it at every declaration and
  reference. No new declaration representation, cache, or traversal.
- **Idiomatic.** The feature is spelled as C storage classes and lowered to
  C `static`; no namespace objects or access-check tree. Recognition sits
  beside `_static_interface_form`, the existing contextual-word pattern.
- **Diagnostics and negative fixtures.** Prefix collision at splice
  (silent merge of two files' statics into one key: wrong output). Static
  shadowing a module name, for objects, functions, and typedefs in either
  order (breaks the deliberate `module` promise: wrong binding). Duplicate
  adopted class tag across members (runtime merges two descriptors:
  corrupted dispatch). Each has one negative fixture. No other validators.
