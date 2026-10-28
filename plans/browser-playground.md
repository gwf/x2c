> Status: reference
> Phases 1 and 2 published to dev on 2026-10-28 through PR #596
> (`b1584a01fffab7b18eaf80afc23fd5fdb19189c6`). The shared integrator
> passed the full publication gate. Phase 3 remains unscoped.
> Planned 2026-10-28 against `gwf/repo-survey-major-features-933090`
> (`f5d0eb2fb`). The original feasibility evidence follows. The runtime
> and three programs
> were compiled to WebAssembly with Emscripten 6.0.13 and run under Node
> 26 during planning; the compiler itself was not compiled to wasm.

# Browser playground

## Requested behavior

The public site gets a playground page where a visitor edits an x2c program,
presses Run, and sees its standard output, with the program running in the
browser as WebAssembly. Gallery example pages get a Run button that executes
the sample shown. Preloaded examples come from `examples/gallery.json`.

## Decisions

- Architecture: hybrid. A service translates `.x` to C and compiles the C
  and the prebuilt wasm runtime to one `.wasm`; the browser instantiates it,
  so user programs never run on the server. A later phase replaces the
  service with the compiler in wasm when its process dependencies are
  removed. Fully server-run execution is the fallback only if the hybrid
  cannot ship; it is not planned.
- Runtime target: `wasm64` (`emcc -m64`, Memory64). The runtime asserts
  `sizeof(long) == 8` and `sizeof(void *) == 8` (`lib/common.x` lines 38
  to 51), `Var` is a NaN-boxed 64-bit word, and the language documents
  `long` as 64-bit; wasm32 fails those assertions in every unit. Making the
  runtime 32-bit clean would change language semantics and is rejected.
  Memory64 shipped in Chrome 133 and Firefox 134 (confirmed 2026-10-28
  from the Chromium and Mozilla intent-to-ship threads). Safari support
  is unconfirmed; phase 1 tests current Safari and records the minimum
  versions on the page. If Safari lacks it, the page says so and the
  fallback in the design review applies.
- Exceptions: `-sSUPPORT_LONGJMP=emscripten`. `lib/exception.x` lowers
  `try` to `sigsetjmp` and `siglongjmp`; the probe's catch, finally, and
  `raise` behave as native.
- Threads: not supported in phase 1. The runtime subset links single
  threaded without `-pthread`; `Thread.start` raises `<io-fail>` when
  `pthread_create` fails, which is the documented failure path.
- Browser runtime subset: all 70 runtime units compile and are archived.
  Exclusions are enforced at the playground, not by a second runtime
  build: programs that use `Job` (`process.x`), `File.popen`, `Thread`,
  `Channel`, `Dispatch`, or `Pool` workers compile but fail at run time
  under Emscripten's stubs; the playground documents this list, and the
  service rejects `#include "process.x"` with a clear message.
- No new language syntax or toolchain code. `X2C_CC=emcc` selects the
  compiler through the existing `Toolchain` lookup order; `--c-flags` and
  `--ld-flags` carry the Emscripten options; the wasm runtime archive is
  passed as an explicit `.a` operand (`build` accepts `.a` operands) with
  `-Wl,--whole-archive`. The toolchain still appends its host
  `libx2c.a`; the Makefile target below links with `emcc` directly, as
  the stage makefiles do, so the host archive is never on the wasm link
  line. Changing `Toolchain._layout` to select a target runtime is deferred
  until a second target needs it.

## Feasibility established by probe

Commands run from the checkout root with `builds/0/x2c` and Homebrew
`emcc` 6.0.13; outputs are under the session scratch directory.

```sh
builds/0/x2c translate --out-dir gen examples/foreach.x examples/tours/language.x
for c in builds/0/lib/*.c; do
  emcc -fsigned-char -O1 -m64 -sSUPPORT_LONGJMP=emscripten \
    -iquote builds/0/lib -iquote include/x2c -c $c -o obj64/$(basename $c .c).o
done
emar rcs libx2c-wasm.a obj64/*.o
emcc -fsigned-char -O1 -m64 -sSUPPORT_LONGJMP=emscripten \
  -iquote builds/0/lib -iquote include/x2c gen/language.c -o language.js \
  -Wl,--whole-archive libx2c-wasm.a -Wl,--no-whole-archive \
  -sALLOW_MEMORY_GROWTH=1 -sEXIT_RUNTIME=1
node language.js
```

Results:

- Without `-m64`, 61 of 70 units fail on the `unsigned long is 8 bytes`
  assertion or its consequence (`duplicate case value` in
  `Var_decode_f64`); 9 header-only units compile.
- With `-m64`, 70 of 70 units compile without warnings, including
  `process.x`, `thread.x`, `mutex.x`, `pool/`, `lisp/`, and `exception.x`.
  Emscripten supplies `pthread`, `fork`, `popen`, and `sigsetjmp` stubs
  or implementations, so nothing needs a source stub.
- `foreach` prints `v = 1..3`; `examples/tours/language.x` (Map, match,
  Scope, Lisp, lambda, defer) matches `examples/expected/docs-tour.stdout`
  byte for byte; a `raise`/`catch`/`finally` probe matches its native run.
- Sizes: `language.wasm` 1.18 MB at `-O1` with the whole archive, 314 KB
  gzipped; the exception probe is 880 KB at `-Os`. Each program carries the
  whole runtime because `-Wl,--whole-archive` keeps protocol tables and
  constructors; a split main/side module is an unverified later
  optimization.
- Generated C for an ordinary program includes only `x2c.h` and
  `exception.h` from `builds/0/lib`; the runtime headers resolve through
  `-iquote builds/0/lib -iquote include/x2c`.
- Translation of these programs ran zero host preprocessor actions
  (`--verbose` shows no `x2c: preprocess`); the prelude replays
  `builds/0/lib/x2c.xi`. The compiler still spawns `cc -E` for a header
  the prelude has not seen, the meta helper for `meta` calls
  (`Frontend.prepare_meta`: inputs that reach none use no helper), and
  `dlopen` for `--native-module`.
- Homebrew `llvm` has no `wasm-ld`, so the `wasi-libc` route was not
  exercised beyond a failed link; `wasmtime` runs the Emscripten `.wasm`
  only with a WASI shim, so CI uses Node.

## Source assessment of the runtime

| Module | Mechanism | Browser status |
| --- | --- | --- |
| `exception.x`, `lisp/evaluate.x` | `sigsetjmp`, `siglongjmp` | Works with `-sSUPPORT_LONGJMP=emscripten`. |
| `mutex.x`, `logger.x`, `static-init.x`, `match/sites.x`, `scope/accounting.x`, `error/handlers.x`, `context.x`, `lisp/sessions.x`, `pool/storage.x` | `pthread_mutex`, `pthread_once` | Portable; Emscripten's single-threaded libc implements them. |
| `thread.x`, `pool/pool.x`, `channel.x`, `dispatch.x`, `thread-state.x` | `pthread_create` | Compiles; `Thread.start` fails at run time. Documented exclusion. `-pthread` with SharedArrayBuffer is a later option that needs COOP/COEP headers on Pages. |
| `lisp/evaluate.x` | `pthread_getattr_np` stack probing | Compiles under Emscripten; stack depth limit set by `-sSTACK_SIZE`. |
| `process.x`, `file.x` (`popen`) | `fork`, `execvp`, `waitpid`, `popen` | Compiles against stubs that fail with `ENOSYS`; excluded by the service. |
| `file.x`, `path.x` | stdio, `opendir` | Works on Emscripten's in-memory FS; nothing persists, which is the intended sandbox. |
| `scan.x` | the `_Thread_local` spelling only | Portable. |
| `common.x` `threaded` storage | `_Thread_local` | Compiles single threaded. |

No module uses `signal`, `mmap`, `dlopen`, `getaddrinfo`, or sockets.

## Compiler in the browser

Compiling `src/` to wasm is plausible but untested. Blockers in source:

- `Toolchain.preprocess` spawns the host `cc -E` for headers outside the
  replayed prelude; a browser build needs an in-process preprocessor or a
  rule that rejects system includes the prelude lacks.
- `Frontend.prepare_meta` builds and spawns a helper process only for
  inputs that reach project `meta` functions, so ordinary programs without
  `$` calls never need it; a no-meta build is a run-time refusal, not a
  source change.
- `src/meta-native/modules.x` uses `dlopen` for `--native-module`; refused
  in the browser.
- `build` and `run` spawn `cc`; the browser build stops at `translate`.

Known in-browser C compilers, all unverified and recorded from memory, none
tested here: binji's `wasm-clang` (clang and lld compiled to wasm, roughly
100 MB download with a sysroot), Emscripten-in-browser experiments, and
`tcc` compiled to wasm (small, but no wasm backend). None is small enough
for a first visit, so the fully client-side path waits for a measured
download budget. Download and latency estimates:

| Path | First-visit download | Run latency | Server load |
| --- | --- | --- | --- |
| Fully client-side | 100 MB or more (clang.wasm) plus x2c.wasm | Seconds per compile in the browser | None |
| Hybrid (chosen) | 0.3 to 1.2 MB per compiled program | One round trip plus a short compile; the probe compiled and linked a program in under 2 s | Translate and compile only; no user code runs |
| Fully server-run | Output only | One round trip plus compile and run | Runs untrusted programs; needs a sandbox |

## Implementation

### Runtime archive: `make wasm-runtime`

`builds/wasm/libx2c.a` is built by a new target in the root `Makefile`:

```make
WASM_CC ?= emcc
WASM_CFLAGS = -fsigned-char -Os -m64 -sSUPPORT_LONGJMP=emscripten \
  -iquote builds/0/lib -iquote include/x2c
wasm-runtime: build
	mkdir -p builds/wasm/lib
	for c in builds/0/lib/*.c; do \
	  $(WASM_CC) $(WASM_CFLAGS) -c $$c -o builds/wasm/lib/$$(basename $$c .c).o; done
	emar rcs builds/wasm/libx2c.a builds/wasm/lib/*.o
```

It reuses the C that stage 0 already translated; no second translation
and no change to `etc/x2c.mk` or `builds/stage.mk`. The target is
optional, like `commands-check`, and is not part of `make check`.

### Program build: `tools/wasm-build`

A shell script that takes one `.x` file and an output stem:

```sh
builds/0/x2c translate --out-dir "$tmp" "$input"
emcc $WASM_CFLAGS "$tmp/$stem.c" -o "$out.js" \
  -Wl,--whole-archive builds/wasm/libx2c.a -Wl,--no-whole-archive \
  -sALLOW_MEMORY_GROWTH=1 -sEXIT_RUNTIME=1 -sMODULARIZE=1 \
  -sEXPORT_ES6=1 -sENVIRONMENT=web,node -sINITIAL_MEMORY=64MB \
  -sMAXIMUM_MEMORY=256MB -sSTACK_SIZE=4MB
```

The same script serves CI and the service. Translation errors are returned
as the service response body with exit status 1.

### Service

An HTTP endpoint `POST /compile` with source text as the body and an
`application/json` response containing `loader` (ES module source) and
`wasm` (base64 bytes). Errors return JSON with an `error` string.
`plans/networking-and-flagship-service.md` plans `lib/http.x` but has
status `needs author scoping`; the playground does not wait for it. Phase
2 ships a container (`etc/playground/Dockerfile`) with the Linux x2c
release, Emscripten, and a small Node handler calling `tools/wasm-build`.
When `lib/http.x` lands, the handler is rewritten in x2c as a second
flagship example; the endpoint contract stays. Limits: 64 KB source,
one compile per client per 5 s, 20 s compile timeout, result cached by
source hash. The source must not include `process.x`; other excluded
modules fail at run time with their documented errors.

### Site embedding

- `site/src/pages/playground.astro`: editor (a `textarea` with the shiki
  highlighted overlay already used for samples), example selector, Run
  button, output pane, and a browser-support notice. No framework is added;
  `site/package.json` keeps Astro, satteri, and shiki.
- `site/src/lib/playground.ts`: posts the source, instantiates the module
  with `WebAssembly.instantiate`, and runs it in a Web Worker so an infinite
  loop can be terminated. `Module.print` and `Module.printErr` append to the
  output pane; `stdout` and `stderr` are shown in order with `stderr`
  dimmed. A run is terminated after 10 s or 256 MB; the worker is
  recreated for every run.
- Gallery pages: `ExamplePanel.astro` gains a Run button when the article's
  slide is in `examples/gallery.json`; the button opens the playground with
  that example preloaded (`/playground/?example=love/maps`), so example
  pages stay static. Preloaded examples are the `gallery.json` entries
  whose example is not in the excluded list, read at build time by
  `site/src/lib/examples.ts`.
- Pages deployment is static; the service URL is `PLAYGROUND_URL` at site
  build time, and the page hides Run when it is unset.

### CI

`.github/workflows/check.yml` gains an optional job `wasm-runtime` with the
same manual trigger: install Emscripten (`mymindstorm/setup-emsdk`), `make
build-safe`, `make wasm-runtime`, `tools/wasm-build examples/tours/language.x`,
and `node language.js | diff - examples/expected/docs-tour.stdout`. It is
advisory like the rest of that workflow and never required.

### Security

- User programs run only in the visitor's browser, in a Web Worker, with
  Emscripten's in-memory filesystem; nothing reaches the server besides
  source text.
- The service runs `x2c translate` and `emcc` on untrusted text; `x2c
  translate` can execute native compile-time code, so each request runs
  as an unprivileged user with no network, a read-only image, a 20 s
  timeout, and a 512 MB memory limit per request. `#include` of absolute
  paths and `..` is rejected before translation.
- Memory and time limits on the client are `MAXIMUM_MEMORY` and the worker
  timeout above.

## Phases

1. Runtime and build script (about 150 lines of Makefile, script, and a
   `docs/src/internals/building.md` section): `make wasm-runtime`,
   `tools/wasm-build`, the CI job, and the recorded browser support check.
2. Service container and site page (about 400 lines across
   `etc/playground/`, `site/src/pages/playground.astro`,
   `site/src/lib/playground.ts`, and `site/src/styles/`): the endpoint,
   the page, and the gallery Run buttons.
3. Migration toward fully client-side (unscoped): remove the compiler's
   process dependencies behind a `translate`-only build, measure an
   in-browser C compiler, and decide from the measured download.

## Validation

- Phase 1: `make wasm-runtime` succeeds; `tools/wasm-build` on
  `examples/foreach.x`, `examples/tours/language.x`, and
  `examples/power/exceptions.x` matches each `expected` output under Node.
- Phase 2: `make site-check` passes; `npm --prefix site test` gains one
  test that the page renders without `PLAYGROUND_URL`; a browser run in
  Chrome, Firefox, and Safari of the three programs above. Record unavailable
  browser automation as a coverage gap; do not claim inferred support as tested.
- Delivery follows `AGENTS.md`: code and build changes use
  `tools/gate-state.py ensure agent-pr-check`; the site page alone uses
  `doc-check` plus `make site-check`.

## Design review

- Reuse: the archive is built from the C stage 0 already wrote, with the
  include order `Toolchain._compile_arguments` uses; no second translation,
  no new compiler flag, no toolchain change.
- Boundaries: exclusions are documented run-time failures of existing
  contracts (`Thread.start` raising `<io-fail>`) rather than a trimmed
  runtime with its own test matrix.
- Risk: Memory64 browser support is the one external premise; phase 1
  records the measured minimum versions, and the page states them. If
  Safari support proves missing, the page reports the unsupported browser.
  A server-run fallback requires a separate decision because it changes the
  execution boundary.
- Risk: the service runs compile-time code from strangers; the container
  limits above are the mitigation, and the cache by source hash bounds
  repeated cost.

## Last implementation step

Review the completed diff against this plan before publication validation:
confirm no change to `etc/x2c.mk`, `builds/stage.mk`, or `src/toolchain.x`,
that `make check` is unchanged, that the site builds without the service
URL, and that the book section describes only what shipped. Then run the
validation command for the delivered change.

## Implementation details settled on 2026-10-28

- The service returns loader source and wasm bytes in one JSON response.
  The browser worker passes the bytes to the Emscripten module factory.
- Each compile runs in a separate restricted container. The HTTP handler
  does not execute submitted source on its own host.
- `examples/power/exceptions.x` reads `examples/data/power-exceptions`;
  Node validation and the service embed these existing fixture files.
  Other filesystem examples need their own data or remain excluded.
- [Chrome 133 release notes](https://developer.chrome.com/release-notes/133)
  document Memory64. [WebKit Technology Preview 252 notes](https://webkit.org/blog/18304/release-notes-for-safari-technology-preview-252/)
  add Memory64; that does not establish support in stable Safari.
  The page detects Memory64 directly and reports unsupported browsers.
  The server-run fallback is not part of this implementation.
- Phase 3 requires a separate scope decision and is not an implementation
  deliverable in this batch.

## Implementation review

The optional build reuses stage zero's generated C and the ordinary runtime.
No compiler, toolchain, stage makefile, or existing check target changes.
The worker owns execution and termination; Emscripten owns the memory cap.
The service adds a per-request container because translation can execute
native compile-time code. Include filtering is a user-facing policy, not
the isolation boundary. Its negative checks protect the documented source
limit, include policy, origin policy, request rate, and timeout behavior.

The gallery sweep exposed a pre-existing invalid C variadic call in the
operators example. `Map.update_n` requires Var keys and values. Boxing its
integer value fixes the wasm64 trap and preserves native expected output.
The matching site slide receives the same correction.

Focused evidence: all 70 runtime units compile; the three named programs
match their Node outputs; all 20 selected gallery programs match their
expected outputs after the operators correction. The static site check
passes. Real Chrome and Chromium run the three named programs through the
browser worker. Compile diagnostics, Stop, and the 10-second limit work.

The initial validation lacked a running Docker daemon and supported Firefox
automation. The real-container follow-up below closes the Docker gap.
The site test suite has an unchanged baseline theme assertion failure; its
new playground test passes. Publication validation belongs to the shared
integrator.

## Delivery

PR #596 includes the runtime archive, program build script, optional CI job,
compile service, playground, and gallery links. Follow-up review corrected
the executable tmpfs required by native meta helpers and preserved the
unsupported-browser Run guard after page lifecycle events.

The tested wasm binaries declare 64 MiB initial memory and a 256 MiB
maximum. Repeated browser runs use fresh worker state after completion,
errors, and Stop; responses from aborted compilations are ignored. The
shared integrator passed the full publication gate and confirmed the
remote merged revision. No full gate ran in the author checkout.

Firefox and Safari program execution remain unverified. Installed Firefox
131.0.3 predates Memory64 support; its unsupported notice and disabled Run
button are verified. Public service deployment is not configured. The site
keeps Run hidden until its build receives a service URL. Local Docker
validation does not constitute completed public deployment.

### Real-container follow-up

Starting the installed Docker Desktop made its daemon available. Building
the actual image exposed two packaging defects: the image omitted the
compiler-owned build command sources, and Emscripten attempted mutable
cache writes despite its prewarmed libraries. The Dockerfile now copies
`commands/` and enables supported `EM_FROZEN_CACHE=1` for requests. The
read-only image and request restrictions remain in place.

The corrected ARM64 image builds. Real HTTP requests compile foreach,
the language tour, exceptions, and the native meta example. Returned wasm
exits successfully under Node and matches each expected output. Chrome
also runs fresh compilations of these programs through the actual service
and container with matching output. Docker inspection confirms the
non-root user, no network, read-only image, 512 MiB memory limit, one CPU,
64-process limit, and executable 128 MiB tmpfs. A shortened request
deadline returns 504 and removes the observed running container.

Chrome also displays real compilation diagnostics, stops a running wasm
loop on request, and terminates it automatically after 10 seconds. A
subsequent run succeeds. These checks use the actual HTTP service and
restricted request containers, not the earlier artifact-response fixture.
The local Docker Desktop check does not verify a production rootless host.
