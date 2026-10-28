# Playground compilation service

The Node HTTP handler accepts source at `POST /compile`. It returns JSON:

```json
{"loader":"ES module JavaScript source","wasm":"base64 encoded WebAssembly"}
```

Errors return `{"error":"diagnostic"}` and a non-200 HTTP status. Source is
limited to 64 KiB. Each client address can compile once per five seconds.
Successful results are cached by source hash, with at most 32 entries.
The handler allows two active compilations and returns 503 while busy.
It does not run the resulting WebAssembly.

## Run

Use Node 22 or newer, Docker, and the repository root as the build context:

```sh
docker build -f etc/playground/Dockerfile -t x2c-playground .
PLAYGROUND_ORIGINS=https://x2c.org node etc/playground/server.mjs
```

The image builds the checked-out x2c compiler and wasm runtime. It prewarms
the Emscripten link cache because request containers have a read-only image.
The tiny `examples/data/power-exceptions` fixture is embedded into each
program's in-memory filesystem so the curated exception example can run.
No request receives a host filesystem mount.

Set `PLAYGROUND_ORIGINS` to a comma-separated list of exact site origins.
Set `PLAYGROUND_IMAGE` to select another locally built compiler image.
The handler listens on `127.0.0.1:8787`; `HOST` and `PORT` override this.
Terminate HTTPS at the deployment's reverse proxy. Configure its request
body limit to 64 KiB and its response timeout above 20 seconds.

Build the static site with `PLAYGROUND_URL=https://compile.example`.
The client appends `/compile` to this service base URL. Browser preflight
and responses allow only origins listed in `PLAYGROUND_ORIGINS`.
Requests without an Origin header can be made by command-line clients.
The handler uses the socket client address and ignores forwarded headers.
A proxy therefore shares one rate-limit bucket unless it preserves client
addresses; do not trust arbitrary forwarded headers to bypass this limit.

## Isolation

Run the handler under a dedicated account with access to a dedicated rootless
Docker daemon. That account can control the daemon; do not mount a Docker
socket into compiler containers. Protect the handler host and keep deployment
credentials out of the compiler image and build directories.

Each cache miss starts a fresh container with:

- no network and no host mounts;
- a read-only image and an unprivileged user (`65534:65534`);
- all capabilities dropped and no privilege escalation;
- 512 MiB memory including swap, one CPU, and at most 64 processes;
- one writable 128 MiB `/tmp` tmpfs;
- a 20-second deadline, followed by forced container removal.

The writable tmpfs permits native compile-time helpers to execute. Translation
can execute native compile-time code, so source filtering is not the sandbox.
Literal absolute and parent includes, nonliteral include directives, and
`process.x` are rejected with diagnostics. Other unavailable browser APIs
retain their ordinary runtime failures. The output is capped at 8 MiB.

The browser must run the returned module in a fresh worker with its own
10-second execution limit. The compiler image supplies the wasm memory cap.

## Focused checks

```sh
node --test etc/playground/server.test.mjs
```

These tests exercise HTTP responses, source policy, CORS, rate limiting,
cache reuse, diagnostics, timeout reporting, and Docker arguments and cleanup.
The Docker-runner test uses a fake CLI. Test the real image in a deployment
with a running daemon before exposing the service:

```sh
curl --fail-with-body http://127.0.0.1:8787/compile \
  -H 'Content-Type: text/plain' --data-binary @examples/foreach.x
```

Also verify that timeout removal leaves no `x2c-playground-*` containers and
that the three plan examples compile and execute through the browser worker.
