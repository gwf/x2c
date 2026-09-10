# libuv client

This package provides an x2c interface to the pinned static
libuv 1.52.1 profile. Its entry point is `src/libuv.x`. It
provides one event loop for asynchronous DNS, TCP, named-pipe, UDP, and
filesystem I/O, and process supervision: argv, working directory,
environment, stdin, captured stdout and stderr, exit status, term signal,
deadlines, cross-thread wakeups, timers, signal handling, and directory
watching.

```x2c
import "libuv" with UvLoop, UvProcess;

int main(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();

  UvProcess counted = loop.spawn(%("/usr/bin/wc" "-l"));
  defer counted.free();
  counted.write(%"alpha\nbeta\ngamma\n").close_stdin();
  loop.run(UV_RUN_DEFAULT);

  printf("%s", %"lines: ${counted.stdout()}");
  return 0;
}
```

The archive is `builds/liblibuv.a`, deliberately not `libuv.a`, so it never
collides with the upstream archive it links beside.

## Commands, options, and deadlines

`UvLoop.spawn(argv)` starts a child with no options. When a child needs one,
`UvLoop.command(argv)` returns the same `UvProcess` unstarted;
`directory`, `environment`, `stdio`, `max_output`, and `deadline` configure
it and `start` runs it. Every option is set before the command starts, and
setting one afterwards raises `<bad-state>`.

```x2c
UvProcess check = loop.command(%("/bin/sh" "-c" "make test"))
  .directory(%"/tmp/build")
  .environment(%{"PATH": "/usr/bin:/bin", "MODE": "strict"})
  .stdio(<pipe>, <pipe>, <pipe>)
  .deadline(30000)
  .start();
```

`environment` replaces the child's whole environment rather than extending
it, which is what `uv_process_options_t.env` means; read `uv_os_environ` on
the raw path when the child should inherit and extend.

`stdio(input, output, error)` selects `<pipe>`, `<inherit>`, or `<ignore>` for
each standard stream. The default is three pipes. `write` accepts multiple
queued stdin writes; each write owns its bytes until libuv completes it, and
`close_stdin` queues shutdown after them. Output methods raise `<bad-state>`
when their stream was not configured as `<pipe>`.

A child that outlives its deadline is killed with `SIGKILL`.
`UvProcess.timed_out` reports that afterwards, and tells it apart from the
same `SIGKILL` arriving for another reason.

## Loop callbacks

Seven loop-owned handles take a callback and a `Var` the caller supplies,
which is where callback state lives; the callback receives both.

- `UvLoop.async(value, fn)` creates a coalescing wakeup. `UvAsync.send` is
  thread-safe, but it carries no message: several sends before the loop
  handles them may produce one callback. Put state in `value`, and use an
  x2c `Thread` result only through `Thread.join`.
- `UvLoop.idle(value, fn)` runs every loop turn before prepare and forces
  libuv to poll without waiting. It does not mean "when nothing else is
  active"; leaving it active can busy-spin a CPU.
- `UvLoop.prepare(value, fn)` runs immediately before libuv polls for I/O.
- `UvLoop.check(value, fn)` runs immediately after libuv polls for I/O.
- `UvLoop.timer(delay, repeat, value, fn)` fires once after `delay`
  milliseconds and then every `repeat` milliseconds when `repeat` is
  positive. A repeating timer keeps the loop alive until `UvTimer.stop`.
- `UvLoop.signal(number, value, fn)` handles a signal inside the loop. The
  handle is unreferenced, so it never keeps the loop alive by itself: a
  supervisor still exits when its children finish, and still gets a chance
  to kill them when a signal arrives first.
- `UvLoop.watch(path, value, fn)` reports changes to a file or a directory.
  `UvWatch.entry` copies libuv's reported name, or is absent when libuv
  supplies none. A notification can name the watched directory itself or
  an entry that no longer exists; scan the directory when current files
  are needed.
  `UvWatch.kind` is `<rename>` when the entry appeared, disappeared, or was
  renamed, and `<change>` otherwise. An entry is reported once per event, so
  a caller that wants distinct names keeps a `Map`.

Each handle's `loop` method reaches the loop from inside its callback, so
stopping the loop needs no file-scope state.

## Addresses and DNS

`UvAddress.ip4` and `UvAddress.ip6` construct numeric socket addresses.
`host`, `port`, `family`, `socket_type`, `protocol`, `scope_id`, and
`canonical_name` expose copied fields; `native` returns a stable
`const struct sockaddr *` for a native API such as TCP or UDP.

`UvLoop.resolve(node, service, value, fn)` starts the common `AF_UNSPEC`,
`SOCK_STREAM` lookup immediately. The builder form keeps all four native
`addrinfo` hint fields available:

```x2c
UvLookup lookup = loop.lookup(%"127.0.0.1", %"443")
  .hints(AF_INET, SOCK_STREAM, IPPROTO_TCP,
         AI_NUMERICHOST | AI_NUMERICSERV)
  .start(state, completed);
```

The completion callback uses `count` and checked `address(index)` access.
Every address and canonical name is copied before libuv's result list is
freed, so the same access remains valid after the callback returns.
`UvLookup.cancel` returns true only when libuv accepts cancellation. The
request remains pending until its callback runs with `cancelled` true; a
completed or already-running request returns false.

## TCP clients and servers

`UvLoop.tcp` creates a concrete `UvTcp` for a client or listener. `bind`
accepts an `UvAddress` and native bind flags; `connect` invokes its callback
after the connection completes. `listen` accepts each pending connection
before invoking its callback, which receives the caller-owned accepted
`UvTcp` alongside the listener.

`read` delivers copied `Bytes` chunks and `Bytes NULL` once for ordinary EOF;
it ignores libuv's zero-byte non-events. TCP is a byte stream, so callers
accumulate the bytes they need rather than treating one callback as one
message. An explicit `stop_read` is reversible; EOF is final for that stream.
`write` copies a String and `write_bytes` copies the entire underlying byte
extent, including embedded NUL bytes, before submitting it.
`write_queue_size` reports the native bytes still queued.

`shutdown_write` queues a half-close behind earlier writes. The longer name
is required because x2c reserves `TYPE.shutdown()` for type-wide runtime
teardown. It does not close the read side; use `close` when the connection is
finished. Closing twice is harmless. `local_address` and `peer_address`
return copied addresses, while `loop` and `native` expose the owning loop and
exact `uv_tcp_t *`.

## Named pipes

`UvLoop.pipe` creates a concrete `UvPipe` using ordinary byte streams rather
than libuv's descriptor-passing mode. `bind`, `connect`, and `listen` use a
Unix filesystem path; `listen` receives a caller-owned accepted `UvPipe`.
`read`, `stop_read`, `write`, `write_bytes`, `shutdown_write`, `close`, and
`write_queue_size` have the same stream behavior as TCP.

`local_name` and `peer_name` copy libuv's borrowed endpoint names. An unnamed
client endpoint is the ordinary empty String. Closing a successfully bound
listener removes its socket path on the Unix profile; it does not
remove an unrelated path when bind fails. Existing stale paths remain the
caller's responsibility.

## UDP datagrams

`UvLoop.udp` creates a message-oriented `UvUdp`. `bind` accepts an IP address
and native bind flags; `connect` fixes one peer. `send` copies a String and
`send_bytes` copies an entire binary extent through completion. Their first
argument is the destination for an unconnected handle and `NULL` for a
connected handle. Unlike stream writes, a non-null empty `Bytes` sends a real
empty datagram.

`receive` delivers one copied `Bytes`, copied source `UvAddress`, and the
native flags for each datagram. It ignores only libuv's zero-byte callback
without an address. `UV_UDP_PARTIAL` remains set when the configured buffer
truncates a datagram and the discarded remainder is not delivered later.
`max_receive` sets that positive buffer limit before receiving; the default
is 64 KiB. `stop` is idempotent and receiving may restart afterwards.

`local_address` and `peer_address` return copies. `send_queue_size` counts
queued bytes while `send_queue_count` also counts empty datagrams. `close` is
idempotent; `loop` and `native` expose the owning loop and exact `uv_udp_t *`.

## Asynchronous files

`UvLoop.open(path, flags, mode, value, fn)` returns its `UvFile` through the
completed `UvFs`. A file supports one offset `read`, `write`, or
`write_bytes`, and asynchronous `close`. Each low-level operation reports the
exact native partial byte count through `UvFs.result`; reads return copied
`Bytes`, while both write forms retain their own copy until completion.
`UvFile.close` rejects outstanding operations. After close, file operations
and native descriptor access raise `<bad-state>`.

`UvLoop.read_file` reads through EOF and enforces its byte limit; an exact
limit succeeds only after a one-byte EOF probe. `write_file` and
`write_file_bytes` create or truncate with mode `0666` and repeat partial
writes. These whole-file helpers always close their private descriptor before
reporting completion or the primary Error.

`UvLoop.stat` returns a copied `UvStat`; its common accessors are `mode`,
`size`, `modified_seconds`, and `modified_nanoseconds`, while `native`
reaches the complete copied `uv_stat_t`. `UvLoop.scan` copies every entry name
and `uv_dirent_type_t`; `entry_count`, `entry_name(index)`, and
`entry_type(index)` remain valid after native request cleanup and after the
directory changes.

Every operation has the same callback shape, `fn(UvFs, Var)`. `operation`
identifies the requested `UV_FS_*` operation. For one low-level operation,
`result` is its exact native result. For a successful whole-file request it is
the total byte count; `native` retains the cleaned final open, read, or write
request and therefore retains that request's own `fs_type` and partial result.
The result-specific accessors are `file`, `bytes`, `stat`, and the directory
entry methods. `cancel` returns true only when libuv accepts cancellation; the
request remains alive until its callback runs with `cancelled` true.

## Callbacks and threads

Every callback runs on the thread that called `UvLoop.run`, inside that
call. No callback in this package runs on a libuv worker thread. An x2c
`Thread` may call `UvAsync.send`, then the loop callback may join it and read
its exported result. The sender must be joined before `UvAsync.stop` or
`UvLoop.free`; `send` is a wakeup, never a way to share mutable x2c values.

An x2c Error never unwinds through libuv. Async, DNS, filesystem, TCP and
pipe connect/listen/read, UDP receive, idle, prepare, check, timer, signal,
and watch callbacks invoke user x2c handlers, so they catch and copy the
first Error, stop the affected operation and the current loop run, and
re-raise the original cause and detail after `uv_run` returns to
`UvLoop.run`. The caller may run the loop again after catching it.
Allocation, process, send, stream write, shutdown, deadline, and handle close
callbacks only update native state or report a native failure through that
same stopped-loop path.

Errors keep libuv's own vocabulary: a failing native call raises `<io-fail>`
carrying the operation, the numeric status, `uv_err_name`, and
`uv_strerror`.

## What stays on the raw path

Advanced filesystem operations beyond open, read, write, close, whole-file
I/O, stat, and scan remain on the raw path through `uv-152.h` and
`UvLoop.native`. TTY, low-level poll and fs-poll, dynamic libraries, and
libuv's thread primitives remain raw as well.

Pipe descriptor passing, `uv_pipe_open`, `bind2`/`connect2`, Linux abstract
names, embedded-NUL names, and chmod remain raw as well.
UDP multicast, broadcast, TTL, recvmmsg, socket adoption, disconnect, and
try-send operations also remain raw.

libuv performs filesystem work internally on its worker pool, but reports
completion on the thread driving `UvLoop.run`, so filesystem callbacks may
safely enter x2c. `uv_queue_work` stays raw because its caller-supplied work
body runs on a foreign worker without an x2c Context. Use it only for native
work, or use `lib/thread.x` when the worker body is x2c.

Every wrapper's `native` method returns its exact upstream handle:
`uv_loop_t *`, `uv_process_t *`, `uv_async_t *`, `uv_idle_t *`,
`uv_prepare_t *`, `uv_check_t *`, `uv_timer_t *`, `uv_signal_t *`, or
`uv_fs_event_t *`; TCP exposes `uv_tcp_t *`, named pipes expose `uv_pipe_t *`,
UDP exposes `uv_udp_t *`, lookup requests expose `uv_getaddrinfo_t *`, and
addresses expose `const struct sockaddr *`. Files expose their `uv_file`
descriptor, filesystem requests expose `uv_fs_t *`, and copied stats expose
`const uv_stat_t *`. That is the only supported way to reach a wrapper's
native object; private layout is not a contract.

## No Lisp surface

A loop, a process, a timer, and a watcher are opaque native handles with no
value-oriented Lisp surface: a binding could only hand a session a handle it
cannot do anything with, or run a whole batch inside one call and lose the
supervision that is the point. This package has no Lisp bindings; programs
that need to script a batch stay in x2c.

## Examples

`examples/thread-notify.x` starts one x2c `Thread`, uses `UvAsync.send` to
wake the event loop, joins the worker inside the loop callback, and prints
the result exported by `Thread.join`.

`examples/process-report.x` is the short application (`make short-example`).
In 28 lines it runs two children on one loop, writes each one's stdin,
reads their output back as x2c values, and reports their exit statuses.

`examples/network-report.x` resolves localhost, accepts three loopback TCP
clients, exchanges copied payloads containing NUL bytes, observes both sides'
EOF, and prints one deterministic summary without using the external network.

`examples/ipc-report.x` binds a unique `/tmp` socket path, exchanges a binary
report through a named pipe, copies both endpoint names, observes both EOFs,
and leaves no socket path behind.

`examples/datagram-report.x` sends connected and unconnected loopback
datagrams, preserves an embedded NUL and a real empty packet, and identifies
one deliberately truncated diagnostic through `UV_UDP_PARTIAL`.

`examples/release-checks.x` is the broader application (`make example`). It
supervises a batch of release checks: each is a child in a sandbox directory
with a fixed environment and its own deadline, the loop reports every check
as it finishes rather than at the end, a watcher names the artifacts they
leave behind, asynchronous filesystem requests read their contents after
supervision, and SIGINT or SIGTERM abandons the batch and kills whatever is
still running instead of orphaning it.

```text
4 checks in /tmp/x2c-libuv-release
  environment  ok       strict
  line-count   ok       3
  fingerprint  ok       1253032073
  slow-scan    timed out
  artifact     lines.txt    3
  artifact     sum.txt      1253032073
3 passed, 1 timed out
```

## Ownership and execution

`UvLoop` owns one native loop. Each `UvTcp`, `UvPipe`, and `UvUdp` owns its
native handle; the caller owns every accepted connection delivered by
`listen`, and every submitted stream write or datagram owns private payload
storage until its completion callback. UDP source addresses and received
payloads are copied before the receive callback enters x2c. `UvProcess`
separately owns its process handle, configured stdio pipes, queued writes,
and deadline timer; `UvProcess.free`
releases the captured bytes and raises `<bad-state>` while any of those
handles is still open, so run the loop until the child and its pipes finish
first. Freeing it twice is harmless. Every process query after the first free
raises `<bad-state>` rather than treating the released process as one that
was never started.

Each successful low-level open returns a caller-owned `UvFile`; its descriptor
remains open until its asynchronous close completes. Each `UvFs` owns its path
and I/O buffer through native completion, releases native request storage
before its x2c callback, and retains only copied results afterwards.

`UvLoop.free` closes whatever the caller left open, including TCP, named-pipe,
UDP, async, idle, prepare, check, timer, signal, and watch handles, and drains
their close callbacks. It raises `<bad-state>` while a package DNS, connect,
send, write, shutdown, or filesystem request is pending, or while a `UvFile`
is open, instead of invoking a completion callback from destruction. Run
accepted cancellation and I/O close through completion before freeing the
loop. Join every thread that can send an async notification first. Free the
processes before the loop: their stdio pipes belong to them, not to it.
Putting `defer loop.free()` at the acquisition site orders process and loop
cleanup automatically.

Captured output is copied into x2c values on demand. `UvProcess.stdout` and
`UvProcess.stderr` return `String` and raise `<bad-enc>` when the bytes
contain a NUL; `stdout_bytes` and `stderr_bytes` return `Bytes` for binary
output. Each capture is bounded by `max_output`, 16 MiB by default, and
exceeding it raises libuv's own `ENOBUFS`.

One `UvLoop` is not reentrant and is not safe to drive from two threads.

## Build and test

`make prepare` downloads, verifies, and builds the pinned static profile in
the shared integration cache. `make build` produces `builds/liblibuv.a` and
the generated package header. `make run` and `make test` prepare it
automatically when absent and reuse it when present. Set `X2C_DEPS_DIR` to
move the shared cache, or `LIBUV_PREFIX` to diagnose another compatible
installation.

```sh
make verify-profile
make run
make test
```

`make verify-headers` and `make verify-licenses` check the prepared upstream
headers and the license texts against their reviewed SHA-256 values, and
`make verify-linkage` asserts that the linked example depends on nothing but
`/usr/lib/libSystem.B.dylib`. Nothing links until `verify-profile` passes.

The client and its tests are licensed under
[Apache-2.0](../../LICENSE). libuv
retains the terms reproduced under `LICENSES/`. See `../LICENSE-POLICY.md`
for the project intake policy.
