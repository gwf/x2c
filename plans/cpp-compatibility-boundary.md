> Status: active - Gary authorized implementation and shared-integrator submission.
> Based on published dev f116ed0e1893119973cd2f0c1b7437aaf0e1ee21.
> This plan supersedes the earlier CPP campaign's broader authoring premise.

# CPP as an optional C compatibility bridge

## Result and boundary

Ordinary compiler, runtime, command, and application builds do not run full
C macro expansion or build/replay macro export tables for that expansion.
Native C compilation still performs its normal preprocessing.

Add one `--cpp` switch, off by default, to enable the existing x2c-owned
expansion engine when translating existing C. Use the existing translation,
build, and run option path. Do not infer the mode from filenames, directives,
or a parse failure. Do not repurpose `--cpp-symbols` or `--live-symbols`;
those retain their host-symbol collection purpose. `--no-cpp` retains its
collection-suppression purpose and also suppresses optional expansion.

Neither mode discovers x2c module membership, imports, or meta declarations
manufactured by C macros. Those constructs must be visible as authored x2c
syntax for discovery. This removes the discovery guarantee; it does not
add origin tracking or a validator to reject otherwise legal syntax.

## One coherent implementation

1. Carry the expansion setting through existing request/compiler configuration
   to root parsing and included-source/header declaration collection. Default
   paths bypass expansion, runtime macro acquisition, and CPP export replay.
   Preserve explicit native-header and loaded-macro REPL behavior. Include the
   mode in existing in-memory collection, interface, helper, and build identities
   wherever reuse depends on the parsed result; add no separate cache.
2. Return module and meta discovery to authored syntax. Preserve literal module
   splicing, nested members, source locations, private names, imports, helper
   ownership, and dependency invalidation. Remove discovery-only macro export
   preparation, its temporary carriers and CPP-only collection branches, and
   splice reconstruction for macro-generated module blocks. Keep ordinary
   declaration collection and the export replay still used by `--cpp` or REPL.
3. Separate the narrow directive handling our existing code actually requires
   from full expansion. Preserve necessary directive emission, native constants
   and macro calls, platform guards, declaration prefixes, and layout handling.
   Do not blindly restore every historical conditional hack or retain the new
   CPP evaluator on the default path. Resolve exceptional cases against their
   concrete consumers; do not turn CPP on globally to preserve an accommodation.
4. Remove tests and documentation promising CPP-generated x2c constructs.
   Move genuine C expansion cases behind `--cpp`. State that CPP is a bridge
   for existing C, without promoting it for new x2c code. Preserve unrelated
   review repairs and ordinary module/meta tests. Do not adopt either held
   prototype or the unoptimized initializer experiment.
5. Check the behavior and cost below, then review and fix the complete authored
   diff before publication validation. Submit the coherent result through the
   replacement shared integrator; it owns final artifacts and the full gate.

## Focused evidence before submission

- Default mode: ordinary modules/meta functions, imports, native headers,
  constants, necessary platform guards, and representative compiler/runtime
  translations work without expansion or CPP export replay. Check cold and
  populated interfaces and switching modes in the same cache.
- CPP mode: retain grammar-producing C cases represented by cJSON iteration,
  sds statements, stb_sprintf statement arguments, and tinyexpr type arguments,
  plus C declaration/field macros and relevant existing replay controls. Use
  retained sources where available. Distinguish reduced cases from whole-library
  success; do not claim complete ports without that evidence.
- Preserve native REPL header collection, imported macro use, and ordinary
  authored module/meta behavior. Synthetic CPP-generated x2c constructs are
  not acceptance criteria and do not justify replacement machinery.
- Use existing focused checks, required stage two, and applicable performance
  checkpoints. Compare default builds with pinned current dev using the same
  complete stage-three workload and flags. Separate elapsed times from
  instruction counts and disclose host interference. Promise no unmeasured
  saving or twenty-second result. Add no recurring gate or validation target.

## Design review

This uses one switch and the current engine, and deletes discovery machinery
serving an unendorsed use. It does not replace the preprocessor, redesign the
cache, or expand CPP support. The source comparison establishes these removal
targets, not a validated replacement. The principal correctness risks are
conditional handling currently coupled to expansion, mode-dependent cache
reuse, and new native REPL consumers. Check those directly during implementation.
