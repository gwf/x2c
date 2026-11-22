# Close the WebAssembly runtime gaps

> Status: Implemented and verified locally on 2026-11-21. Based on
> `78e92517a` and Emscripten 6.0.13. No PR has been submitted.

Use the existing x2c APIs in the Memory64 runtime. Start with secure random
and stack bounds in the default build. Then add selectable builds for threads
and cooperative tasks. Give browser apps access to selected and persistent
files through the loader and the existing `File` and `Path` APIs.

Keep the current single-threaded loader as the default. Native builds keep
their existing ABI, runtime behavior, and build sequence. Use the existing
optional WebAssembly checks and focused probes. Publication follows the
existing integrator workflow.

## 1. Secure random and stack bounds

**Secure random.** In [lib/random.x](../lib/random.x), select `getentropy`
under Emscripten. Fill buffers in chunks of at most 256 bytes. Report provider
failure through the existing `Random.secure_fill` error path. Both
`Random.from_entropy` and `Uuid.v4` already call `Random.secure_fill`.
The current build fails to link any of the three because it calls Linux
`getrandom`. The pinned Emscripten SDK returned success from `getentropy`
for 256 bytes in a Memory64 program under Node. Its browser implementation
uses Web Crypto.

**Stack bounds.** In [lib/thread-state.x](../lib/thread-state.x), use
`emscripten_stack_get_end()` for the current Emscripten C stack. Keep the
existing reserve calculation and the installed task bound's precedence.
Keep the platform lookup at the existing owner. JSON, regex, the datum reader,
and Lisp already call that owner. A Memory64 probe verified that the API
reported bounds containing the current frame. The Wasm engine's call stack
has its own limit. Check that the native-style x2c error occurs before a
browser trap on the supported recursion paths. If a path hits the engine's
limit first, bring back that path and the input that reproduces it before
changing its recursion policy. [Emscripten stack API](https://emscripten.org/docs/api_reference/stack.h.html)

**Acceptance.** Exercise the three entropy APIs through `tools/wasm-build`.
Reuse the [random tests](../unittest/test-random.x) and cover requests of 0,
256, 257, and several hundred bytes. Check UUID version and variant. Exercise
normal and deep inputs through the existing JSON, regex, and Lisp suites or
focused drivers of the same public entry points. Check that a handled depth
error leaves the module usable. Run the existing Wasm examples and focused
native checks for both source owners. Verify the two platform calls in a
browser as well as under Node.

## 2. Threads, channels, and mutexes

Add an opt-in pthread build through [the runtime target](../Makefile) and
[tools/wasm-build](../tools/wasm-build). Compile the runtime and consumers
with `-pthread` and link with `-pthread`. Keep the pthread archive and object
paths distinct from the default runtime. Reuse Emscripten pthreads and x2c's
existing Thread, Channel, Mutex, and parallel-iterator implementations.

In the browser, run `main` on the Emscripten runtime-owning dedicated Worker.
Load the generated launcher from a stable URL so its pthread Workers can
load the matching artifacts. Prewarm a configurable pool before starting
`main`. Set `PTHREAD_POOL_SIZE_STRICT=2` so exhausting the pool returns through
the existing `Thread.start` error path. Document the pool size as the
concurrent pthread capacity of this browser build. Serve the runner in a
cross-origin-isolated context with the required response headers. The live
examples pages did not send those headers when checked on 2026-11-21.
[Emscripten pthreads](https://emscripten.org/docs/porting/pthreads.html)

Both thread lessons and `power/channels` produced the expected output and
exited under Node with a prewarmed pool and `main` on the runtime thread.
With `PROXY_TO_PTHREAD`, even `foreach` raised `Error.pop out of order` during
shutdown. Keep the runtime owner and `main` on the same Worker for the first
browser build. If the browser cannot support that arrangement, bring back
the startup or shutdown evidence before changing runtime ownership.

**Acceptance.** Run both lessons and the channel example in a cross-origin-
isolated browser and compare stdout and exit status. Reuse the thread,
channel, mutex, and batch suites to check contention, rendezvous, cancellation,
worker Error propagation, and parallel iterator results. Check that exceeding
the configured pool reports the existing launch failure and leaves the
application able to join its workers. Verify that the browser runner reports
missing cross-origin isolation before starting a threaded module. Enable
the threaded site examples only where the deployed runner meets those
conditions.

## 3. Cooperative `Task.run`

Add an Emscripten backend at [lib/task/stack.c](../lib/task/stack.c) for an
opt-in Asyncify build. Keep the existing backend interface and the scheduler
in [lib/task.x](../lib/task.x). Use Emscripten fibers with a C stack and an
Asyncify continuation buffer per suspended fiber. Let the backend own both
buffers and report the task's C-stack bound through the existing interface.
Use the existing task stack setting for C-stack capacity. The Asyncify
buffer is additional memory. Measure the per-task cost at the current 8 MiB
C-stack default before deciding the continuation budget. Preserve allocation
failure handling. Measure Wasm size and peak memory against the default
build for the same workload. [Emscripten fibers](https://emscripten.org/docs/api_reference/fiber.h.html)

A standalone Memory64 fiber resumed and transferred control through
`siglongjmp` under Node. A scratch backend produced both expected replies
from the cooperative half of `channel-service.x`. The loader did not report
`onExit`. Make normal return, nonzero exit, and x2c shutdown work through the
loader before offering the profile. The first profile can run on one Worker.
Combining fibers with pthreads or the x2cui JSPI build needs its own evidence.

**Acceptance.** Run the existing task and channel batch tests that exercise
park/resume, cancellation, Error and `defer` after resumption, and repeated
batches. Check that completion and failure reclaim stacks and preserve the
caller's runtime state. Compare the `channel-service.x` task results in Node
and a browser. Verify a clean exit and a nonzero exit through the same loader
the browser will use.

## 4. Browser filesystem emulation

Extend [the loader and worker boundary](../site/src/lib/playground-worker.ts).
Emscripten MEMFS already implements the filesystem calls `File` and `Path`
use. Give each run its own virtual filesystem. Copy files selected by the
user to separate input subdirectories before `main` and pass virtual paths
as arguments. Separate subdirectories preserve basenames without overwrites.
Keep generated files in an output directory that the host can offer for
explicit download after the program completes. Run `love/files` and
`power/counting` with either a supplied fixture or a selected file.

Add persistence as an opt-in mount for an application that needs it. Use
IDBFS with a stable, app-specific mount and populate it before `main`.
Keep the Worker alive until the host has flushed closed files after a
successful run and has received the sync result. Only then report that it
saved the files. Prove this ordering with Emscripten's exit and filesystem
hooks before enabling persistence. Use a browser lock per writable mount
across load, execution, and flush so an older snapshot cannot overwrite a
newer save. Stop or trap before a successful run leaves the previous
saved data available. Keep fixture and transient runs on MEMFS.
[Emscripten filesystems](https://emscripten.org/docs/api_reference/Filesystem-API.html)

**Acceptance.** Compare the two file examples' output to the existing
expectations. Exercise binary input and output, duplicate basenames,
missing files, and cancellation. For a persistent mount, check write, rename,
and delete across reload. Check concurrent access and simulated sync failure.
Use the runner's existing error and status path for a failed load or save.

## Follow-up boundary

`Time.local` and `Time.format_local` also have a fixable gap. The current
Emscripten library uses the JavaScript host's time zone. Preserving x2c's
`TZ` behavior requires both IANA zone lookup and POSIX rules. Choose that
backend separately from the sequence above. Native OS process launch,
arbitrary host paths, native sockets, and desktop UI services are outside
this runtime plan.

### Launching another Wasm app

The host can launch another Wasm app in response to an imported function or
message. The current Emscripten build already exports a factory for creating
independent instances. For an independently scheduled app, the host starts
a Worker with that app's loader and Wasm, passes arguments and selected
files, and reports output and exit status. Each app gets its own memory and
filesystem unless the host explicitly supplies sharing. The browser runtime
has no POSIX process to fork. Supporting a native-style `Job` for Wasm
would require a separate contract for launch, waiting, cancellation, and
streams. This plan leaves that interface open.
[Emscripten modularized output](https://emscripten.org/docs/compiling/Modularized-Output.html)

## Local implementation record

- Secure entropy and stack bounds passed focused Memory64 checks in Node and
  Chromium. The browser and Node both handled JSON and regex depth errors.
  After Gary approved a Lisp-specific limit, the Emscripten evaluator raised
  `<call-stack>` at 1,500, 1,750, and 2,000 nested forms, then recovered.
  A 1,000-form input evaluated normally. Native focused random and Lisp
  suites passed.
- Separate pthread and Asyncify archives build locally. The four threaded
  site programs matched expected output under Node and in a cross-origin-
  isolated Chromium page. Browser pool exhaustion and missing-isolation
  errors took the expected paths. Emscripten expanded the Node pool beyond
  its prewarmed size.
- The Task profile passed repeated Error, cancellation, defer, rendezvous,
  and nonzero-exit probes in Node and Chromium. The exit hook ran before the
  reported status 7. A 40-job default-stack allocation failure raised and
  caught `<alloc-fail>` in both environments. The measured 512 KiB Asyncify
  buffer leaves 295,796 bytes above the largest observed saved chain
  (228,492 bytes). The same `foreach` program used 16 MiB linear memory
  in both default and Task profiles; the Wasm files were 865,731 and
  1,727,553 bytes respectively. A prepared task reserves 8 MiB of C stack
  plus 512 KiB of continuation storage.
- The two file examples matched expected output in Chromium with embedded
  fixtures. Selected input, distinct same-name files, binary output,
  persistence across Workers, rename, delete, concurrent runs, a nonzero
  run, and cancellation passed browser probes. Simulated load and save
  failures reported errors rather than completion.
- The full native 1,025-job task batch was not run in WebAssembly: its
  default 8 MiB stack per job exceeds the current 256 MiB maximum memory.
  Thread-plus-Task and Task-plus-JSPI profiles were not built. Browser
  checks used a local server; the current public site lacks COOP/COEP
  headers, so threaded gallery programs remain opt-in. No PR, remote push,
  or publication gate was run.

## Plan review

- Emscripten owns entropy, stack geometry, pthread synchronization, fiber
  context switching, and filesystem operations. x2c supplies only the
  platform selection and the calls those existing owners require.
- Keep the existing Error, scheduler, and file APIs. The pthread archive
  exists because its objects need different compile flags. The fiber buffers
  exist because Emscripten tracks the C stack and continuation separately.
  The persistence lock covers one read-modify-write snapshot at a time.
- Use ordinary build options and existing runtime boundaries. The design
  adds no compiler feature, general process abstraction, or recurring gate.
- The browser runner checks its own cross-origin isolation before loading
  pthreads because the deployment controls that state. Use existing Error
  causes for entropy, recursion, worker, and task failures. Negative checks
  cover depth errors, pool exhaustion, Error after task resumption, and file
  load or save failures. They exercise existing public behavior or prevent a
  false claim that a run saved its data. No new runtime validator is proposed.
