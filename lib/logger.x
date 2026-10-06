/*  logger.x -- owned structured event delivery

    Copyright (c) 2025 Gary William Flake

    Logger owns filtering, event timestamps, sink ordering, and sink lifetime.
    It is reentrant and serializes configuration, sequencing, and delivery.
    Expensive callers may query Logger.should_log before constructing
    canonical field `List`s.

    Events carry one wall-clock timestamp and one monotonic elapsed timestamp.
    Every sink for an event observes the same immutable LogEvent. Built-in text
    sinks render through `Buffer` and `Var.write_repr` without constructing
    canonical presentation `String`s.
*/

#pragma once
#include "common.x"

/** An ordered, reentrant sink dispatcher allocated in the active `Scope`.
    `Logger.free` must run before that `Scope` is released. Memory sinks also
    require the canonical pool captured by `Logger.new` to remain live.
*/
typedef struct Logger *Logger;

/** A borrowed handle to one `Logger`-owned sink registration.
    Removal, clearing, or freeing its `Logger` invalidates the handle; callers
    never free it directly.
*/
typedef struct LogSink *LogSink;

/** Describes one immutable event during synchronous sink delivery.
    The event pointer is valid only for the callback. `fields` is borrowed with
    its caller-provided lifetime, and every sink receives the same value.
*/
typedef struct LogEvent {
  unsigned long sequence;
  long long wall_time_us;
  long long elapsed_us;
  Symbol level, category, List fields;
} LogEvent;

/** Receives one borrowed event and the `data` supplied at registration.
    The callback may log recursively, but it must not retain `event`, mutate
    the active sink list, or free `logger` during delivery.
*/
typedef void (*LogEmitter)(Logger logger, const LogEvent *event, Var data);

/** Flushes one sink with its borrowed registration data.
    The callback must not mutate the active sink list or free `logger`.
*/
typedef void (*LogFlusher)(Logger logger, Var data);

#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <unistd.h>

#include "array.x"
#include "block.x"
#include "buffer.x"
#include "exception.x"
#include "mutex.x"
#include "error.x"
#include "error_init.x"
#include "file.x"
#include "list.x"
#include "pool.x"
#include "scope.x"
#include "string.x"
#include "symbol.x"
#include "var.x"

static typedef void (*LogDataDestructor)(Var data);

static struct LogSink {
  Logger logger;
  struct LogSink *prev, *next, LogEmitter emit, LogFlusher flush;
  LogDataDestructor destroy;
  Var data;
};

static struct Logger {
  Symbol min_level, LogSink first_sink, last_sink, int emission_depth;
  unsigned long sequence;
  long long origin_monotonic_us;
  Scope owner_scope, Pool pool, Scope storage;
};

static typedef struct LogTextSink {
  File file, Block scratch, int color, flush_each, depth;
} *LogTextSink;

static typedef struct LogMemorySink {
  List *destination, Pool pool, Scope *destination_scope, values;
  Block wide_values;
} *LogMemorySink;

#include "var-adapters.x"
$var.pointer(LogTextSink, logtextsink, <p48>);
$var.pointer(LogMemorySink, logmemorysink, <p48>);

static protocol Var(LogTextSink) as void *;
static protocol Var(LogMemorySink) as void *;

static Logger global_logger = NULL, default_logger = NULL;
static ErrorHandler logger_error_handler = NULL;
static int logger_error_mark, static pthread_mutex_t logger_mutex;
static pthread_once_t logger_mutex_once =
  (pthread_once_t) PTHREAD_ONCE_INIT;

// synchronization

static void _mutex_initialize(void) =>
  Mutex.recursive_initialize(
    &logger_mutex, "Logger: could not initialize mutex");

static void _lock(void) =>
  Mutex.recursive_lock(
    &logger_mutex, &logger_mutex_once, _mutex_initialize,
    "Logger: could not lock mutex");

static void _unlock(void) =>
  Mutex.recursive_unlock(&logger_mutex, "Logger: could not unlock mutex");

static macro Decorator $logger.synchronized(Function $function) {
  _lock();
  defer _unlock();
  $(x2c.function.body $function)...
}

static keyword synchronized $logger.synchronized;

// delivery

/** Delivers one event synchronously to eligible sinks in registration order.
    `fields` is borrowed for the call. All sinks observe one immutable event,
    sequence numbers increase per `Logger`, and elapsed time starts with its
    first delivered event. NULL, filtered, invalid, sinkless, or category-less
    events do nothing. Fatal delivery flushes all sinks afterward.
    Raises: any cause from an emitter or fatal-event flusher; later callbacks
    are then skipped.
*/
synchronized
void Logger.log(Logger logger, Symbol level, Symbol category, List fields) {
  if (!_should_log(logger, level, category)) return;
  long long wall_time, monotonic;
  _capture_time(wall_time, monotonic);
  if (logger.sequence == 0) logger.origin_monotonic_us = monotonic;
  LogEvent event = {
    .sequence = logger.sequence++,
    .wall_time_us = wall_time,
    .elapsed_us = monotonic - logger.origin_monotonic_us,
    .level = level,
    .category = category,
    .fields = fields
  };
  if (event.elapsed_us < 0) event.elapsed_us = 0;
  $let(logger.emission_depth, logger.emission_depth + 1) {
    for (LogSink sink = logger.first_sink; sink; sink = sink.next)
      sink.emit(logger, &event, sink.data);
    if (level == <fatal>) logger.flush();
  }
}

static void _capture_time(long long &wall_time, long long &monotonic_time) {
  struct timeval now, struct timespec monotonic;
  if (gettimeofday(&now, NULL) != 0) {
    now.tv_sec = time(NULL);
    now.tv_usec = 0;
  }
  wall_time = (long long) now.tv_sec * 1000000LL + now.tv_usec;
  if (clock_gettime(CLOCK_MONOTONIC, &monotonic) != 0) {
    monotonic_time = wall_time;
    return;
  }
  monotonic_time =
    (long long) monotonic.tv_sec * 1000000LL + monotonic.tv_nsec / 1000LL;
}

// level filtering

/** Reports whether an event would reach at least one sink.
    A category names an event rather than filtering it. A NULL `Logger` or
    category, no sinks, `<off>`, an invalid level, or a filtered level returns
    zero.
*/
synchronized
int Logger.should_log(Logger logger, Symbol level, Symbol category) =>
  _should_log(logger, level, category);

/** Reports whether the current global `Logger` would deliver this event. */
synchronized
int log_should_log(Symbol level, Symbol category) =>
  _should_log(global_logger, level, category);

static inline int _should_log(Logger logger, Symbol level, Symbol category) {
  if (!logger || !category || !logger.first_sink) return 0;
  int priority = _level_priority(level);
  if (priority < 0 || priority >= 6) return 0;
  return priority >= _level_priority(logger.min_level);
}

static inline int _level_priority(Symbol level) {
  switch (level) {
    case <trace>: return 0;
    case <debug>: return 1;
    case <info>:  return 2;
    case <warn>:  return 3;
    case <error>: return 4;
    case <fatal>: return 5;
    case <off>:   return 6;
  }
  return -1;
}

/** Returns the ordering priority of a built-in level, or -1 when invalid.
    Priorities run from `<trace>` at zero through `<off>` at six.
*/
int Logger.level_priority(Symbol level) => _level_priority(level);

/** Returns `logger`'s minimum enabled level, or the null `Symbol` for NULL. */
synchronized
Symbol Logger.min_level(Logger logger) => logger ? logger.min_level : 0;

/** Sets the minimum enabled level and returns one.
    A NULL `Logger` or invalid level returns zero without changing anything.
*/
synchronized
int Logger.set_min_level(Logger logger, Symbol level) {
  if (!logger || _level_priority(level) < 0) return 0;
  logger.min_level = level;
  return 1;
}

/* sinks

   Sink nodes and built-in sink state are in the Logger's private Scope.
   Callback sinks borrow `data`; retiring them invalidates the handle without
   releasing anything reachable through that value. Built-in destructors
   release only their wrapper storage and never close a borrowed File. */

/** Appends a callback sink and returns its `Logger`-owned handle.
    A NULL `Logger` returns NULL; a quiescent `Logger` also returns NULL for a
    NULL emitter. The `Logger` borrows `data` and both callbacks until the
    sink is removed, cleared, or the `Logger` is freed, so anything they
    reference must remain live. Emitters run synchronously in registration
    order.
    Raises: `<bad-state>` during active sink delivery, or `<alloc-fail>` when
    the sink cannot be allocated.
*/
synchronized
LogSink Logger.add_sink(
  Logger logger, LogEmitter emit, LogFlusher flush, Var data) {
  _require_quiescent(logger, "Logger.add_sink");
  return _new_sink(logger, emit, flush, data, NULL);
}

/** Removes and invalidates `sink`, returning one when it belonged to `logger`.
    When quiescent, a NULL argument, foreign sink, or already retired sink
    returns zero.
    Raises: `<bad-state>` during active sink delivery.
*/
synchronized
int Logger.remove_sink(Logger logger, LogSink sink) {
  _require_quiescent(logger, "Logger.remove_sink");
  if (!logger || !sink || sink.logger != logger || !sink.emit) return 0;
  _unlink_sink(logger, sink);
  _retire_sink(sink);
  return 1;
}

/** Removes and invalidates every sink from `logger`.
    A NULL `Logger` does nothing.
    Raises: `<bad-state>` during active sink delivery.
*/
synchronized
void Logger.clear_sinks(Logger logger) {
  _require_quiescent(logger, "Logger.clear_sinks");
  if (!logger) return;
  LogSink sink = logger.first_sink;
  logger.first_sink = logger.last_sink = NULL;
  while (sink) {
    LogSink next = sink.next;
    _retire_sink(sink);
    sink = next;
  }
}

/** Returns the number of configured sinks, or zero for a NULL `Logger`. */
synchronized
int Logger.sink_count(Logger logger) {
  if (!logger) return 0;
  int count = 0;
  for (LogSink sink = logger.first_sink; sink; sink = sink.next) count++;
  return count;
}

/** Calls configured flushers synchronously in registration order.
    A NULL `Logger` does nothing. A cause raised by a flusher transfers
    immediately, so later sinks are not flushed. A flusher must not mutate the
    sink list or free its `Logger`.
*/
synchronized
void Logger.flush(Logger logger) {
  if (!logger) return;
  $let(logger.emission_depth, logger.emission_depth + 1)
    for (LogSink sink = logger.first_sink; sink; sink = sink.next)
      if (sink.flush) sink.flush(logger, sink.data);
}

static LogSink _new_sink(
  Logger logger, LogEmitter emit, LogFlusher flush, Var data,
  LogDataDestructor destroy) {
  LogSink result = NULL;
  defer if (!result && destroy) destroy(data);
  if (!logger || !emit) return NULL;
  LogSink sink = Scope.calloc_in(&logger.storage, 1, sizeof(struct LogSink));
  *sink = (struct LogSink) {
    .logger = logger, .emit = emit, .flush = flush, .destroy = destroy,
    .data = data};
  _append_sink(logger, sink);
  return result = sink;
}

/* Emission walks the sink list, so changing it from inside an emitter raises,
   as freeing the Logger during delivery does. */
static void _require_quiescent(Logger logger, String owner) {
  if (logger && logger.emission_depth != 0)
    raise %(bad-state (operation $owner));
}

static void _append_sink(Logger logger, LogSink sink) {
  sink.prev = logger.last_sink;
  sink.next = NULL;
  if (logger.last_sink) logger.last_sink.next = sink;
  else logger.first_sink = sink;
  logger.last_sink = sink;
}

static void _unlink_sink(Logger logger, LogSink sink) {
  if (sink.prev) sink.prev.next = sink.next;
  else logger.first_sink = sink.next;
  if (sink.next) sink.next.prev = sink.prev;
  else logger.last_sink = sink.prev;
  sink.prev = sink.next = NULL;
}

static void _retire_sink(LogSink sink) {
  if (!sink) return;
  if (sink.destroy) sink.destroy(sink.data);
  sink.prev = sink.next = NULL;
  sink.emit = NULL;
  sink.flush = NULL;
  sink.destroy = NULL;
  sink.data = void;
}

// text sinks

/** Adds a text sink for borrowed `stderr` and returns its `Logger`-owned
    handle. The sink selects color from terminal state at registration and
    flushes after every event. A NULL `Logger` returns NULL.
    Raises: `<alloc-fail>` or `<bad-enc>` when sink state cannot be
    represented.
*/
synchronized
LogSink Logger.add_stderr_sink(Logger logger) =>
  _add_text_sink(logger, stderr, isatty(fileno(stderr)), 1);

/** Adds a plain-text sink for borrowed `file` and returns its handle.
    The caller must keep `file` open until the sink is removed or the `Logger`
    is freed. Removing the sink flushes but never closes the `File`. A NULL
    argument returns NULL.
    Raises: `<alloc-fail>` or `<bad-enc>` when sink state cannot be
    represented.
*/
synchronized
LogSink Logger.add_file_sink(Logger logger, File file) =>
  _add_text_sink(logger, file, 0, 0);

static LogSink _add_text_sink(
  Logger logger, File file, int color, int flush_each) {
  if (!logger || !file) return NULL;
  LogTextSink context = Scope.calloc_in(
    &logger.storage, 1, sizeof(struct LogTextSink));
  int handed_off = 0;
  Var data = context;
  defer if (!handed_off) _destroy_text(data);
  context.file = file;
  context.color = color;
  context.flush_each = flush_each;
  $scope(&logger.storage) {
    context.scratch = Block.new(sizeof(Buffer));
  }
  handed_off = 1;
  return _new_sink(logger, _emit_text, _flush_text, data, _destroy_text);
}

static void _emit_text(Logger logger, const LogEvent *event, Var data) {
  LogTextSink context = data;
  if (!logger || !context || !context.file || context.depth < 0) return;
  if (context.depth == (int) context.scratch.length)
    _add_scratch(logger, context);
  Buffer *buffers = context.scratch.bytes;
  Buffer out = buffers[context.depth].clear();
  $let(context.depth, context.depth + 1) {
    _render_text(out, event, context.color);
    context.file.write(out.content.bytes, 1, out.content.length);
    if (context.flush_each) fflush(context.file);
  }
}

/* Each nested emission renders into its own Buffer. Appending may grow the
   backing store, so the Buffer and the store live in logger storage, outside
   the caller's transient scope. */
static void _add_scratch(Logger logger, LogTextSink context) {
  $scope(&logger.storage) {
    Buffer added = Buffer.new(0), int appended = 0;
    defer if (!appended) added.free();
    context.scratch.append(&added, 1);
    appended = 1;
  }
}

static void _flush_text(Logger logger, Var data) {
  LogTextSink context = data;
  if (context && context.file) fflush(context.file);
}

static void _destroy_text(Var data) {
  LogTextSink context = data;
  if (!context) return;
  if (context.file) fflush(context.file);
  if (context.scratch != NULL) {
    Buffer *buffers = context.scratch.bytes;
    for (size_t i = 0; i < context.scratch.length; i++) buffers[i].free();
    context.scratch.free();
  }
  Scope.free(context);
}

// text rendering

static const char *_color_reset = "\x1b[0m", *_color_time = "\x1b[90m";
static const char *_color_category = "\x1b[36m", *_color_key = "\x1b[97m";
static const char *_color_string = "\x1b[32m", *_color_literal = "\x1b[35m";
static const char *_color_symbol = "\x1b[34m", *_color_other = "\x1b[37m";
static const char *_color_warn = "\x1b[33m", *_color_error = "\x1b[31m";
static const char *_color_fatal = "\x1b[91m";

static void _render_text(Buffer out, const LogEvent *event, int color) {
  _write_elapsed(out, event.elapsed_us, color);
  _write_label(out, event.level, event.category, color);
  if (event.sequence == 0) _write_start_time(out, event.wall_time_us, color);
  foreach (List field, event.fields) {
    if (!field) continue;
    out.write(" ");
    _write_field(out, field, color);
  }
  out.write_char('\n');
}

static void _write_elapsed(Buffer out, long long elapsed_us, int color) {
  long long milliseconds = elapsed_us / 1000LL;
  long long minutes = milliseconds / 60000LL;
  long long seconds = (milliseconds / 1000LL) % 60LL;
  long long millis = milliseconds % 1000LL;
  if (color) out.write(_color_time);
  out.printf("%lld:%02lld.%03lld", minutes, seconds, millis);
  if (color) out.write(_color_reset);
}

/* The label is ` level/category`, each part in its own color. */
static void _write_label(
  Buffer out, Symbol level, Symbol category, int color) {
  out.write(" ");
  if (color) out.write(_level_color(level));
  _write_symbol(out, level);
  if (color) out.write(_color_reset);
  out.write("/");
  if (color) out.write(_color_category);
  _write_symbol(out, category);
  if (color) out.write(_color_reset);
}

/* A Logger's first event also records the wall-clock time it started. */
static void _write_start_time(Buffer out, long long wall_time_us, int color) {
  out.write(" ");
  if (color) out.write(_color_key);
  out.write("start_time");
  if (color) out.write(_color_reset).write(_color_time);
  out.write("=");
  if (color) out.write(_color_reset).write(_color_string);
  out.write_char('"');
  _write_absolute_time(out, wall_time_us);
  out.write_char('"');
  if (color) out.write(_color_reset);
}

static void _write_field(Buffer out, List field, int color) {
  if (!field) return;
  Var (key, value) = field;
  if (color) out.write(_color_key);
  _write_field_key(out, key);
  if (color) out.write(_color_reset).write(_color_time);
  out.write("=");
  if (color) out.write(_color_reset).write(_value_color(value));
  value.write_repr(out);
  if (color) out.write(_color_reset);
}

static Buffer _write_field_key(Buffer out, Var key) {
  if (key is <symbol>) return _write_symbol(out, key);
  if (key is <string>) return out.write(key);
  return key.write_str(out);
}

static Buffer _write_symbol(Buffer out, Symbol symbol) {
  char bytes[32] = { 0 };
  symbol.decode(bytes);
  return out.write(bytes);
}

static Buffer _write_absolute_time(Buffer out, long long wall_time_us) {
  time_t seconds = (time_t) (wall_time_us / 1000000LL);
  struct tm tm_info, char bytes[64] = { 0 };
  if (!localtime_r(&seconds, &tm_info))
    return out.write("1970-01-01 00:00:00.000");
  size_t length = strftime(bytes, sizeof bytes, "%Y-%m-%d %H:%M:%S", &tm_info);
  int millis = (int) ((wall_time_us % 1000000LL) / 1000LL);
  snprintf(bytes + length, sizeof bytes - length, ".%03d", millis);
  return out.write(bytes);
}

static const char *_level_color(Symbol level) {
  switch (level) {
    case <trace>: return _color_time;
    case <debug>: return _color_symbol;
    case <info>:  return _color_string;
    case <warn>:  return _color_warn;
    case <error>: return _color_error;
    case <fatal>: return _color_fatal;
  }
  return _color_string;
}

static const char *_value_color(Var value) {
  if (value is <string>) return _color_string;
  if (value is <symbol>) return _color_symbol;
  Symbol kind = value.kind();
  if (kind == <integer> || kind == <floating>) return _color_literal;
  return _color_other;
}

/* memory sinks

   A memory sink interns List cells and copied canonical values through the
   pool captured by Logger.new; a canonical hit may still belong to an
   ancestor pool. Wide boxes cannot live there, so they remain in a private
   Scope until sink retirement moves them to the Logger's owning Scope. Other
   pointer-bearing values stay borrowed. */

/** Adds a sink that prepends captured events to `destination`.
    The destination pointer is borrowed until the sink is retired. Entry
    `List`s, `String`s, and Lisp symbols are interned through the pool
    captured by `Logger.new`; a canonical hit may retain an ancestor pool's
    lifetime. Wide values move to the `Logger`'s owning `Scope` on retirement,
    while other pointer-bearing values remain borrowed. Newest events appear
    first.
    A NULL `Logger` or destination returns NULL.
    Registration may raise `<alloc-fail>` or `<bad-enc>` while constructing
    sink state. Later event delivery may raise `<alloc-fail>`, `<size-limit>`,
    or `<bad-enc>` while retaining values.
*/
synchronized
LogSink Logger.add_memory_sink(Logger logger, List *destination) {
  if (!logger || !destination) return NULL;
  LogMemorySink context = Scope.calloc_in(
    &logger.storage, 1, sizeof(struct LogMemorySink));
  context.destination = destination;
  context.pool = logger.pool;
  context.destination_scope = &logger.owner_scope;
  context.values = Scope.new_named("Logger memory values");
  $scope(&logger.storage) {
    context.wide_values = Block.new(sizeof(Var));
  }
  return _new_sink(logger, _emit_memory, NULL, context, _destroy_memory);
}

static void _emit_memory(Logger logger, const LogEvent *event, Var data) {
  (void) logger;
  LogMemorySink l = data;
  List entry = l._cons_retained(event.fields, NULL);
  entry = List.cons_in(l.pool, event.category, entry);
  entry = List.cons_in(l.pool, event.level, entry);
  entry = l._cons_retained(Var.box_long_long(event.elapsed_us), entry);
  entry = l._cons_retained(Var.box_long_long(event.wall_time_us), entry);
  entry = l._cons_retained(Var.box_ulong(event.sequence), entry);
  *l.destination = List.cons_in(l.pool, entry, *l.destination);
}

static List LogMemorySink._cons_retained(
  LogMemorySink l, Var value, List tail) =>
  List.cons_in(l.pool, l._retain(value), tail);

static void _destroy_memory(Var data) {
  LogMemorySink context = data;
  Var *values = context.wide_values.bytes;
  for (size_t i = 0; i < context.wide_values.length; i++)
    values[i].move_wide_to(context.destination_scope);
  context.wide_values.free();
  Scope.destroy(context.values);
  Scope.free(context);
}

static Var LogMemorySink._retain(LogMemorySink l, Var value) {
  if (value.is_null() || value.is_nil() || value is <symbol>) return value;
  if (value.is_wide()) return l._retain_wide(value);
  if (value.is_integer() || value.is_floating()) return value;
  if (value is <string>) return l._retain_string(value);
  if (value is <lsym>) return l._retain_lisp_symbol(value);
  if (value is <list>) return l._retain_list(value);
  return value;
}

static Var LogMemorySink._retain_wide(LogMemorySink l, Var value) {
  Var copy;
  $scope(&l.values) { copy = value.clone_wide(); }
  l.wide_values.push(&copy);
  return copy;
}

static Var LogMemorySink._retain_string(LogMemorySink l, Var value) {
  if (_pool_chain_owns(l.pool, value)) return value;
  String string = value;
  return String.new_in(l.pool, string, string.len());
}

static Var LogMemorySink._retain_lisp_symbol(LogMemorySink l, Var value) {
  String spelling = value.str();
  if (_pool_chain_owns(l.pool, spelling)) return value;
  String copy = String.new_in(l.pool, spelling, spelling.len());
  return Var.new(<lsym>, copy);
}

/* Stage retained heads and rebuild the spine backwards, so a flat List uses
   constant native stack; only nesting recurses. A retained tail is shared. */
static List LogMemorySink._retain_list(LogMemorySink l, List list) {
  if (!list || _pool_chain_owns(l.pool, list)) return list;
  Block heads = $auto(Block.new(sizeof(Var)));
  List tail = list;
  while (tail && !_pool_chain_owns(l.pool, tail)) {
    Var head = l._retain(tail.car);
    heads.push(&head);
    tail = tail.cdr;
  }
  Var *items = heads.bytes;
  for (size_t i = heads.length; i; i--)
    tail = List.cons_in(l.pool, items[i - 1], tail);
  return tail;
}

static int _pool_chain_owns(Pool pool, Var value) {
  for (Pool owner = pool; owner; owner = owner.up)
    if (owner.owns(value)) return 1;
  return 0;
}

// the process logger

/** Installs a borrowed global `Logger` and returns the previous borrowed
    value. Neither `Logger` is flushed, freed, or otherwise retained by this
    call; the installed `Logger` must remain live until it is replaced or
    shutdown runs.
*/
synchronized
Logger log_set_global_logger(Logger logger) {
  Logger previous = global_logger;
  global_logger = logger;
  return previous;
}

/** Returns the borrowed current global `Logger`, or NULL when none is set. */
synchronized
Logger log_get_global_logger(void) => global_logger;

/** Delivers one event synchronously through the current global `Logger`.
    With no global `Logger` this is a no-op; otherwise delivery and failures
    are those of `Logger.log`.
*/
synchronized
void log_event(Symbol level, Symbol category, List fields) {
  global_logger.log(level, category, fields);
}

/** Offers the newest `Error` to the current global `Logger`.
    A well-formed entry with `<abort>` or `<log>` policy is rendered as an
    `<err-report>` event; missing, malformed, `<collect>`, and `<ignore>` input
    produces no event. The borrowed input is never consumed, `data` is ignored,
    and the handler always returns `<declined>`, leaving transfer to `Error` or
    another handler.
    Raises: any cause from `Logger` delivery.
*/
synchronized
Symbol Logger.error_handler(List errors, Var data) {
  (void) data;
  Logger logger = log_get_global_logger();
  if (!logger || !errors) return <declined>;
  Var newest = errors.last();
  if (newest is not <list>) return <declined>;
  List entry = newest;
  Var code = entry.assoc(<code>);
  if (code is not <symbol>) return <declined>;
  Symbol policy = Error.policy_get(code);
  if (policy != <abort> && policy != <log>) return <declined>;
  logger.log(<error>, <err-report>, entry);
  Error.note_rendered();
  return <declined>;
}

// level shorthands

static macro Unit $logger.method(Name $method, Literal $level) {
  /** Logs borrowed `fields` synchronously at $method level under `category`.
      Delivery and failure behavior follow `Logger.log`.
  */
  void Logger.$method(
    Logger $(x2c.ident "logger"), Symbol $(x2c.ident "category"),
    List $(x2c.ident "fields")) {
    ($(x2c.ident "logger")).log(
      $level, $(x2c.ident "category"), $(x2c.ident "fields"));
  }
}

$logger.method(trace, <trace>);
$logger.method(debug, <debug>);
$logger.method(info, <info>);
$logger.method(warn, <warn>);
$logger.method(error, <error>);
$logger.method(fatal, <fatal>);

static macro Unit $logger.global(
  Name $method, Name $function, Literal $level) {
  /** Logs borrowed `fields` globally at $method level under `category`.
      Delivery and failure behavior follow `log_event`.
  */
  void $function(Symbol $(x2c.ident "category"), List $(x2c.ident "fields")) {
    log_event($level, $(x2c.ident "category"), $(x2c.ident "fields"));
  }
}

$logger.global(trace, log_trace, <trace>);
$logger.global(debug, log_debug, <debug>);
$logger.global(info, log_info, <info>);
$logger.global(warn, log_warn, <warn>);
$logger.global(error, log_error, <error>);
$logger.global(fatal, log_fatal, <fatal>);

// lifecycle

/** Creates a `Logger` in the active `Scope`, filtering below `min_level`.
    The `Logger` borrows the active canonical pool for any memory sinks and
    owns a private `Scope` for sink state. An invalid level returns NULL.
    Raises: `<alloc-fail>` when the `Logger` or its private `Scope` cannot be
    allocated.
*/
synchronized
Logger Logger.new(Symbol min_level) {
  if (_level_priority(min_level) < 0) return NULL;
  Logger logger = Scope.calloc(1, sizeof(struct Logger));
  *logger = (struct Logger) {
    .min_level = min_level, .owner_scope = *Scope.top(),
    .pool = Pool.current(), .storage = Scope.new_named("Logger")};
  return logger;
}

/** Flushes and retires every sink, then releases `logger` and its storage.
    Borrowed `File`s and callback data are not released. The global and default
    slots are cleared when they refer to this `Logger`. A NULL `Logger` does
    nothing.
    Raises: `<bad-state>` during sink delivery, or any cause from a flusher.
    Either failure leaves the `Logger` and all sinks live; earlier flushers may
    already have run.
*/
synchronized
void Logger.free(Logger logger) {
  if (!logger) return;
  _require_quiescent(logger, "Logger.free");
  logger.flush();
  logger.clear_sinks();
  if (global_logger == logger) global_logger = NULL;
  if (default_logger == logger) default_logger = NULL;
  Scope.destroy(logger.storage);
  logger.storage = NULL;
  Scope.free(logger);
}

/** Installs the process-wide info-level `Logger` and stderr sink.
    `Error` initializes first, then this function records its handler watermark
    and installs an observing `Error` handler. Runtime initialization calls
    this once and later shutdown hooks invoke `Logger.shutdown` before `Error`
    shuts down.
    Raises: any cause from `Error` or `Logger` initialization.
*/
synchronized
void Logger.initialize(void) {
  Error.initialize();
  default_logger = Logger.new(<info>);
  default_logger.add_stderr_sink();
  global_logger = default_logger;
  logger_error_mark = Error.mark();
  logger_error_handler = Error.push(Logger.error_handler, void);
}

/** Shuts down process-wide `Logger` integration.
    Pending root `Error`s are offered to the active `Logger` before the
    observing handler is removed. The global slot is then cleared; a custom
    active `Logger` is flushed but remains caller-owned, while the default
    `Logger` is flushed, retired, and freed. A repeated call after shutdown is
    a no-op.
    Raises: `<alloc-fail>` while opening the temporary canonical pool,
    `<bad-state>` when default-`Logger` delivery is active, or any cause from
    event delivery or a sink flusher. The failure may interrupt the remaining
    cleanup.
*/
synchronized
void Logger.shutdown(void) {
  Logger active = global_logger;
  if (logger_error_handler) {
    if (active) _log_pending(active);
    // exit() can run shutdown while newer registrations are still live
    Error.trim(logger_error_handler, Error.count());
    Error.pop(logger_error_handler);
    logger_error_handler = NULL;
  }
  global_logger = NULL;
  if (active && active != default_logger) active.flush();
  if (default_logger) {
    // a sink that called exit() abandoned its delivery; nothing can resume it
    default_logger.emission_depth = 0;
    default_logger.free();
  }
  default_logger = NULL;
}

/* Offers the root Errors recorded since initialization to `active`. */
static void _log_pending(Logger active) {
  Pool.open_named("Logger shutdown errors");
  List pending = Error.since(logger_error_mark);
  foreach (List entry, pending) active.log(<error>, <err-report>, entry);
  Pool.close();
}
