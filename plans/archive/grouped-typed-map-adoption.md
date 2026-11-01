# Adopt grouped storage for typed Maps

> Status: done - 2026-10-31.
> Runtime adoption published to dev at `9ef736b22`, after integrating `d211420b4`.
> The publication gate and full benchmark campaign passed. Typed Map is 1.34x
> Boost and Var Map is 3.17x typed on the common integer cohort. The old typed
> control is 2.65x Boost. All count/checksum oracles pass. See the
> [full report](../../unittest/benchmarks/hash-table/results/grouped-adoption-20261031.md).
> Linux/GCC remains untested because Docker was unavailable. Rosetta x86_64,
> native, forced-scalar and sanitizer focused checks pass. Build cost is
> higher across the combined revision and is not isolated to Map adoption.

## Result and boundaries

Make grouped storage the default for MapIntInt, MapLongDouble,
MapStringString, MapStringInt and MapSubInt. Preserve public methods, container
record layouts and signatures, capacity meaning, Scope ownership, borrowing, conversions
and failure behavior. Bucket order can change under the existing traversal
contract. Var Map and Pool retain their Robin Hood storage.

Start from the selected `no-lanes` source archived under
`debug/dev-benchmark-rerun-20261031/source/rebuilt/`. Retain grouped control
bytes, tombstone cleanup, specialized addition, cached String/counting-map
hashes, selective growth helpers and the lookup-mask deletion. Do not introduce
a runtime backend selector, compatibility detection, new allocator or lock.

Evidence at 255de641f: 81 focused tests/5,455 assertions and two million
independent dictionary operations pass in normal, sanitizer and scalar builds.
The matched integer score is 1.36x Boost versus 2.63x for production typed Map.
String replacement is 2.2% above the preceding experiment, with overlapping
sample ranges. MapLongDouble performance and Linux/GCC execution remain to be checked.
Adoption checks pass 81 tests/5,455 assertions plus two million
independent operations in normal, forced-scalar, Rosetta x86_64 and sanitizer
builds. Docker is unavailable; Rosetta is not Linux/GCC evidence.

## Work sequence

1. **Integrate once.** Bring in current origin/dev and preserve a reproducible
   Robin Hood control before editing. Move the selected backend and SIMD helper
   into normal runtime owners under lib/map. Internal entry/control formats
   change together; all supported targets use eight-byte pointers. Reuse shared public operations,
   observation, ownership and publication code. Consolidate cached/uncached
   storage mechanics without runtime dispatch or per-entry rebuild calls.
   Replace experimental pragmas with existing warning-free function attributes.
   Wire the helper into ordinary build/bootstrap header copying. Update the
   book through its authoritative sources and documented generation targets.

2. **Close the specific gaps.** Use the existing typed/substring/Context/
   ownership suites and independent differential checks. Move necessary tiny
   capacity, tombstone and owner-transfer cases into those existing suites.
   Check Linux/GCC and Clang plus the non-ARM scalar path using available
   configured environments; do not install or alter host toolchains. Add a
   focused LongDouble performance comparison and repeat paired String
   replacement measurements. Fix a reproducible regression; surface an
   unresolved performance/compatibility tradeoff before publication.

3. **Finish integration and correctness.** Review the complete authored diff,
   remove copied machinery and debugging code, integrate current origin/dev,
   and commit the exact candidate. Use the existing publication command
   `tools/gate-state.py ensure agent-pr-check` for bootstrap regeneration,
   strict builds, self-host comparison and the remaining correctness checks.
   Reuse unchanged evidence. No new recurring gate or test target is planned.

4. **Reserve a quiet machine and measure the integrated tree.** Finish builds
   before requesting the window. Identify other active agents using Postbag or
   the desktop chat tools. If the host is busy, tell the responsible agents
   that this run needs a bounded quiet window: pause builds, heavy tests,
   profiling and benchmarks; state the expected window and announce release.
   Wait for actual host quiescence as well as responses. Never kill others'
   work. If coordination cannot obtain a quiet host, report that blocker and
   leave timing pending rather than publish noisy headline numbers.

   Freeze the candidate and control revisions, binaries, flags and inputs.
   Run families sequentially: official PLSO and the retained custom suite;
   runtime/compiler/build-cost observations; direct and full integer/String
   hash profiles; the common 24-table count/mixed comparison; all four
   end-to-end word-count paths; all c2x2c versions; Notes HTTP,
   mutex/database-thread/Go and in-process Thread/Task; Match-cache acceptance.
   Keep the previous sample counts and exact count/checksum/API oracles.
   Label the new default as production grouped Map and the old backend as
   the retained control. Guard individual timing samples where supported;
   retain and rerun affected samples, not already-clean campaigns. Keep CPU,
   wall time, adjusted RSS and total RSS distinct. Confirm a suspected
   regression with a targeted paired rerun before expanding measurement.

5. **Publish and report.** Update the summary and single shared-baseline chart
   from the completed quiet run. Record exact source/runtime/binary/input
   hashes and all discarded attempts. Release the quiet window promptly.
   Publish the validated coherent batch to dev under the existing direct
   delivery rules; do not advance main. If upstream advances, integrate and
   validate the delta, repeating only evidence its changes invalidate. Report
   the published revision, default backend, results and any remaining limits.
   Archive this plan when delivery completes.

## Resource rules

Use bounded read-only review help during integration. Keep implementation and
correctness builds separate from timing. Use focused probes while editing;
run the broad correctness command on the final integrated tree and the full
end-to-end campaign once in the reserved quiet window. Preserve known-good
controls and inputs rather than rebuilding historical experiments repeatedly.
These are instructions for this adoption, not additions to precommit or CI.

## Plan review

- Existing factories establish valid power-of-two capacity and padded controls;
  bounded insert/rebuild writes preserve padding. Lookup relies on these facts.
  Existing Scope/Context boundaries continue to own lifetimes and transfers.
- Reuse existing family operations, record accessors, observers, conversions
  and ownership operations. Keep only algorithm-specific grouped probing,
  control matching and tombstone cleanup in the new storage owner. Cached
  hashes avoid repeated String/view hashing during rebuild; the counter
  remains attached to its control allocation rather than adding public state.
- Use ordinary x2c family generation and existing function attributes. Do not
  retain a second copy of the public API or add a backend framework.
- No new validators, dedicated diagnostics or recurring gates are proposed.
  Focused cases exercise the changed storage boundaries: tiny-table padding,
  deleted-slot reuse, cleanup/growth, borrowed keys and owner preservation.
  They protect lookup correctness and storage lifetime, not earlier rejection.
- End implementation with authored/generated-diff review before publication
  validation. Passing tests and fast measurements do not expand the scope.
