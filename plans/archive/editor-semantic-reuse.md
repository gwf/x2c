> Status: done
> Investigation completed 2026-09-12; no implementation justified by callers.
> Delivery commit subject: `overlap native fingerprints and close research probes`.
> Revisit with a measured editor workload showing reusable analysis.

# Editor semantic reuse

The editor compiles each diagnostics, hover, or definition request afresh.
This repeats frontend work, but revision alone does not establish that the
result remains valid. Keep the current implementation until a measured
request pattern and its validity boundary justify reuse.

## Current owners and findings

- `etc/vsc-extension/extension.js` debounces diagnostics for 200 ms per
  document. Document updates, file notifications, and configuration changes
  invalidate or replace the service. Hover and definition providers each
  submit one request with their own query kind and byte offset.
- `etc/vsc-extension/semantic.js` snapshots open documents and starts a fresh
  worker. A newer query for the same file and kind cancels the previous
  query. Revision checks discard responses after invalidation; cancellation
  kills the worker process group before removing snapshots.
- `src/editor.x` creates an isolated compiler context, runs the ordinary
  frontend, and emits diagnostics plus one requested hover or definition.
  It then closes that context. Returning all semantic facts would change
  the protocol and retain or serialize more data.
- Compile-time Lisp can read arbitrary files through `lisp_read_file` in
  `lib/lisp.x`. The extension's file watcher covers selected source suffixes,
  not every possible macro input. A persistent cache keyed by open-document
  revision would therefore have an incomplete invalidation boundary.

## Measurement and decision

The existing semantic and provider tests passed: 11 tests, using
`node --test etc/vsc-extension/test/semantic.test.js
etc/vsc-extension/test/providers.test.js`.

A controlled transport probe submitted two identical overlapping hover
queries, delaying its stub worker by 40 ms. It launched two workers and
returned null for the superseded query and a result for the newer one.
This establishes the current cancellation behavior, not an observed editor
workload or a measured compiler speedup.

Sharing only an identical in-flight request could avoid that second launch
without retaining a completed cache. However, it would need separate caller
cancellation ownership so a superseded hover cannot cancel its replacement.
Current repository callers do not establish a useful frequency of identical
overlap: diagnostics already debounce, changed inputs invalidate, and hover
and definition are different requests. No service or compiler change was
made for this speculative saving.

The next useful evidence is a bounded real-editor trace of query kind,
offset, revision, start/end, cancellation, and worker time. If that shows
material identical overlap, prototype in-flight sharing and verify both
superseded-caller cancellation and invalidation. If distinct queries dominate,
measure frontend cost and design a dependency-complete analysis lifetime
before adding persistent reuse. No new user obligations or recurring checks
follow from this investigation.

## Plan review

Existing snapshot, revision, process-group cancellation, and isolated-context
owners establish the current safety boundary. No new cache, validator,
diagnostic, test requirement, or lifecycle state is introduced. The rejected
prototype idea would add cancellation ownership without a demonstrated
benefit; preserving the existing implementation is the smaller result.
