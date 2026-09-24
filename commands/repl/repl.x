/*  repl.x -- terminal client for persistent compiler submissions

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "cli.x"

typedef struct ReplOptions {
  int dump, stats, verbose_stats;
} ReplOptions;

#pragma private
#include "repl-session.x"
#include "repl-input.x"
#include "diagnostics.x"
#include "lisp.x"
#include "file.x"
#include <stdio.h>
#include <unistd.h>

struct ReplCompleteContext {
  ReplSession session;
  String pending;
};

struct ReplCommand {
  String spelling, synopsis, description;
  Symbol argument, dispatch;
};

static const struct ReplCommand _commands[] = {
  { ":help", ":help", "Show this help.", <none>, <help> },
  { ":stats", ":stats [verbose]", "Show live runtime statistics.",
    <statmode>, <stats> },
  { ":symbols", ":symbols", "List session-defined names and kinds.",
    <none>, <symbols> },
  { ":ast", ":ast NAME", "Show a session function's typed AST.",
    <function>, <ast> },
  { ":lowered", ":lowered NAME", "Show a session function's lowered Lisp.",
    <function>, <lowered> },
  { ":cancel", ":cancel", "Discard incomplete input.", <none>, <cancel> },
  { ":quit", ":quit", "Leave the session.", <none>, <quit> }
};

static const struct ReplCommand *_command(String spelling) {
  for (size_t i = 0; i < sizeof(_commands) / sizeof(*_commands); i++)
    if (_commands[i].spelling == spelling) return _commands + i;
  return NULL;
}

static int _space(unsigned char byte) =>
  byte == ' ' || byte == '\t' || byte == '\r' || byte == '\n';

static List _command_candidates(String prefix) {
  Array candidates = [];
  for (size_t i = 0; i < sizeof(_commands) / sizeof(*_commands); i++)
    if (_commands[i].spelling.startswith(prefix))
      candidates.push(%(<command> ${_commands[i].spelling}));
  return candidates.list_free();
}

static ReplInputCompletion _complete_command(
  ReplSession session, String text, size_t cursor, size_t first) {
  size_t command_end = first;
  while (command_end < cursor && !_space(text[command_end])) command_end++;
  if (command_end == cursor) {
    String prefix = String.new_len(text + first, cursor - first);
    return (ReplInputCompletion) {
      .start = first, .end = cursor,
      .candidates = _command_candidates(prefix)
    };
  }
  String spelling = String.new_len(text + first, command_end - first);
  const struct ReplCommand *command = _command(spelling);
  size_t start = command_end;
  while (start < cursor && _space(text[start])) start++;
  if (!command) return (ReplInputCompletion) { .candidates = %() };
  if (command->argument == <statmode>) {
    String prefix = String.new_len(text + start, cursor - start);
    List candidates = "verbose".startswith(prefix)
                    ? %((keyword "verbose")) : %();
    return (ReplInputCompletion) {
      .start = start, .end = cursor, .candidates = candidates
    };
  }
  if (command->argument != <function>)
    return (ReplInputCompletion) { .candidates = %() };
  String prefix = String.new_len(text + start, cursor - start);
  return (ReplInputCompletion) {
    .start = start, .end = cursor,
    .candidates = session.complete_functions(prefix)
  };
}

static ReplInputCompletion _complete_input(
  void *raw, String text, size_t cursor) {
  struct ReplCompleteContext *context = raw;
  size_t first = 0;
  while (first < text.len() && _space(text[first])) first++;
  if (first < text.len() && text[first] == ':' && cursor < first)
    return (ReplInputCompletion) { .candidates = %() };
  if (first < text.len() && text[first] == ':')
    return _complete_command(context.session, text, cursor, first);
  size_t offset = context.pending.len();
  ReplCompletion completion = context.session.complete(
    context.pending + text, offset + cursor);
  if (completion.start < offset)
    return (ReplInputCompletion) { .candidates = %() };
  List candidates = completion.candidates;
  if (!offset && !text.len()) {
    Array merged = [];
    foreach (Var candidate, _command_candidates("")) merged.push(candidate);
    foreach (Var candidate, candidates) merged.push(candidate);
    candidates = merged.list_free();
  }
  return (ReplInputCompletion) {
    .start = completion.start - offset,
    .end = completion.end - offset,
    .candidates = candidates
  };
}

typedef struct ReplStatsSnapshot {
  unsigned definitions;
  LispAutoStats evaluation;
  MachineStats machine;
  ScopeStats scope;
  PoolStats pool;
} ReplStatsSnapshot;

typedef struct ReplSizeDelta {
  char sign;
  size_t magnitude;
} ReplSizeDelta;

static ReplStatsSnapshot _stats_snapshot(
  ReplSession session, Pool pool, MachineStats *machine) {
  ReplStatsSnapshot stats;
  stats.definitions = session.names.len();
  stats.evaluation = session.compiler.macro_lisp.auto_stats();
  stats.machine = *machine;
  stats.scope = Scope.stats();
  stats.pool = Pool.stats(pool);
  return stats;
}

static ReplSizeDelta _size_delta(size_t now, size_t before) {
  if (now >= before)
    return (ReplSizeDelta) { .sign = '+', .magnitude = now - before };
  return (ReplSizeDelta) { .sign = '-', .magnitude = before - now };
}

static void _write_stats(
  File out, ReplSession session, Pool pool, MachineStats *machine,
  ReplStatsSnapshot baseline, int verbose) {
  ReplStatsSnapshot now = _stats_snapshot(session, pool, machine);
  long calls = now.evaluation.invocations - baseline.evaluation.invocations;
  long entries =
    now.evaluation.machine_entries - baseline.evaluation.machine_entries;
  long errors =
    now.evaluation.machine_errors - baseline.evaluation.machine_errors;
  ReplSizeDelta live = _size_delta(
    now.scope.live_allocations, baseline.scope.live_allocations);
  ReplSizeDelta live_bytes = _size_delta(
    now.scope.live_requested_bytes, baseline.scope.live_requested_bytes);
  size_t allocations =
    now.scope.allocation_calls - baseline.scope.allocation_calls;
  size_t frees = now.scope.free_calls - baseline.scope.free_calls;
  size_t reallocations =
    now.scope.reallocation_calls - baseline.scope.reallocation_calls;
  size_t requested = now.scope.requested_bytes - baseline.scope.requested_bytes;
  size_t interned = now.pool.interned - baseline.pool.interned;
  size_t promoted = now.pool.promoted - baseline.pool.promoted;
  size_t block_allocations =
    now.pool.block_allocations - baseline.pool.block_allocations;
  size_t block_reuses = now.pool.block_reuses - baseline.pool.block_reuses;
  size_t slot_reuses = now.pool.slot_reuses - baseline.pool.slot_reuses;

  out.printf("session: definitions=%u\n", now.definitions);
  out.printf("evaluation (since REPL open): calls=%ld "
    "machine-entries=%ld machine-errors=%ld\n", calls, entries, errors);
  out.printf("evaluation: live-program-bytes=%ld\n",
    now.evaluation.program_bytes);
  out.printf("scope (process): live-allocation-objects=%zu "
    "delta-since-open=%c%zu live-requested-bytes=%zu "
    "byte-delta-since-open=%c%zu\n",
    now.scope.live_allocations, live.sign, live.magnitude,
    now.scope.live_requested_bytes, live_bytes.sign, live_bytes.magnitude);
  out.printf("scope (process, since REPL open): allocation-calls=%zu "
    "free-calls=%zu reallocation-calls=%zu requested-traffic-bytes=%zu\n",
    allocations, frees, reallocations, requested);
  out.printf("pool (current level, since REPL open): "
    "interned-identities=%zu promotions=%zu\n", interned, promoted);
  out.printf("pool (process): backing-capacity-bytes=%zu active-bytes=%zu "
    "active-blocks=%zu depot-bytes=%zu depot-blocks=%zu\n",
    now.pool.backing_bytes, now.pool.active_bytes, now.pool.active_blocks,
    now.pool.depot_bytes, now.pool.depot_blocks);
  out.printf("pool (process, since REPL open): block-allocations=%zu "
    "block-reuses=%zu slot-reuses=%zu\n",
    block_allocations, block_reuses, slot_reuses);
  if (!verbose) return;
  out.printf("evaluation (verbose, since REPL open): analyses=%ld "
    "published=%ld ineligible=%ld guard-failures=%ld "
    "remembered-fallbacks=%ld inlined-scopes=%ld inline-declines=%ld\n",
    now.evaluation.analyses - baseline.evaluation.analyses,
    now.evaluation.published - baseline.evaluation.published,
    now.evaluation.ineligible - baseline.evaluation.ineligible,
    now.evaluation.guard_failures - baseline.evaluation.guard_failures,
    now.evaluation.remembered_fallbacks -
      baseline.evaluation.remembered_fallbacks,
    now.evaluation.inlined_scopes - baseline.evaluation.inlined_scopes,
    now.evaluation.inline_declines - baseline.evaluation.inline_declines);
  out.printf("scope (process, verbose): live-scopes=%zu "
    "scope-creations=%zu scope-destructions=%zu largest-request-bytes=%zu "
    "peak-live-requested-bytes=%zu\n",
    now.scope.live_scopes,
    now.scope.scope_creations - baseline.scope.scope_creations,
    now.scope.scope_destructions - baseline.scope.scope_destructions,
    now.scope.largest_request, now.scope.peak_live_requested_bytes);
  out.printf("pool (verbose): depth=%d allocation-calls=%zu free-calls=%zu "
    "requested-traffic-bytes=%zu\n", now.pool.depth,
    now.pool.allocation_calls - baseline.pool.allocation_calls,
    now.pool.free_calls - baseline.pool.free_calls,
    now.pool.requested_bytes - baseline.pool.requested_bytes);
  out.printf("machine (since REPL open): scan-cells=%ld retries=%ld calls=%ld "
    "returns=%ld max-frames=%d\n",
    now.machine.scan_cells - baseline.machine.scan_cells,
    now.machine.retries - baseline.machine.retries,
    now.machine.calls - baseline.machine.calls,
    now.machine.returns - baseline.machine.returns,
    now.machine.max_frames);
  out.printf("machine: range-comparisons=%ld final-range-comparisons=%ld "
    "span-descriptors=%ld cons-requests=%ld\n",
    now.machine.range_comparisons - baseline.machine.range_comparisons,
    now.machine.final_range_comparisons -
      baseline.machine.final_range_comparisons,
    now.machine.span_descriptors - baseline.machine.span_descriptors,
    now.machine.cons_requests - baseline.machine.cons_requests);
  out.printf("machine: materialization-requests=%ld completions=%ld "
    "avoided=%ld materialized-cells=%ld direct-shares=%ld\n",
    now.machine.materialization_requests -
      baseline.machine.materialization_requests,
    now.machine.materialization_completions -
      baseline.machine.materialization_completions,
    now.machine.materializations_avoided -
      baseline.machine.materializations_avoided,
    now.machine.materialized_cells - baseline.machine.materialized_cells,
    now.machine.direct_shares - baseline.machine.direct_shares);
  out.printf("machine: local-loads=%ld capture-loads=%ld global-loads=%ld "
    "nil-edges=%ld nil-taken=%ld\n",
    now.machine.local_loads - baseline.machine.local_loads,
    now.machine.capture_loads - baseline.machine.capture_loads,
    now.machine.global_loads - baseline.machine.global_loads,
    now.machine.nil_edges - baseline.machine.nil_edges,
    now.machine.nil_taken - baseline.machine.nil_taken);
  out.printf("machine: prepared-calls=%ld native-calls=%ld lisp-returns=%ld\n",
    now.machine.prepared_calls - baseline.machine.prepared_calls,
    now.machine.native_calls - baseline.machine.native_calls,
    now.machine.lisp_returns - baseline.machine.lisp_returns);
}

static void _help_row(String synopsis, String description, size_t width) {
  printf("  %-*s  %s\n", (int) width, synopsis, description);
}

static void _help(void) {
  size_t width = 0;
  for (size_t i = 0; i < sizeof(_commands) / sizeof(*_commands); i++)
    if (_commands[i].synopsis.len() > width) width = _commands[i].synopsis.len();
  puts("Enter declarations or statements with semicolons.\n\nCommands");
  for (size_t i = 0; i < sizeof(_commands) / sizeof(*_commands); i++)
    _help_row(_commands[i].synopsis, _commands[i].description, width);
  puts("\nEditing");
  _help_row("Tab", "Complete names; press again to list choices.", width);
  _help_row("Arrow keys", "Move the cursor or recall history.", width);
  _help_row("Home/End", "Move to the start or end of the edit.", width);
  _help_row("Ctrl-C", "Cancel the current input.", width);
  _help_row("Ctrl-D", "Exit from an empty line.", width);
  puts("\nOptions");
  _help_row("--dump", "Print typed AST and lowered Lisp.", width);
  _help_row("--stats", "Print runtime statistics at exit.", width);
  _help_row("--verbose-stats", "Print detailed statistics at exit.", width);
}

static int _stats_mode(String command, int *verbose) {
  Array words = $auto([]);
  foreach (String word, command.words()) words.push(word);
  if (words.len() == 1) {
    *verbose = 0;
    return 1;
  }
  if (words.len() == 2 && words[1] == "verbose") {
    *verbose = 1;
    return 1;
  }
  return 0;
}

static int _inspect(
  ReplSession session, const struct ReplCommand *descriptor, String command) {
  Array words = $auto([]);
  foreach (String word, command.words()) words.push(word);
  if (descriptor->dispatch == <symbols>) {
    if (words.len() != 1)
      fprintf(stderr, "usage: %s\n", descriptor->synopsis);
    else {
      printf("%%%s\n", session.symbols().repr());
      return 1;
    }
  }
  else if (descriptor->dispatch == <ast> ||
           descriptor->dispatch == <lowered>) {
    if (words.len() != 2) {
      fprintf(stderr, "usage: %s\n", descriptor->synopsis);
      return 0;
    }
    String name = words[1];
    match (session.inspect(name)) {
      case %(function (typed ?syntax) (lowered ?forms)): {
        if (descriptor->dispatch == <ast>)
          printf("typed: %%%s\n", syntax.repr());
        else printf("lowered: %s\n", forms.repr());
        return 1;
      }
    }
    fprintf(stderr, "not a session function: %s\n", name);
  }
  return 0;
}

/** Runs the experimental REPL on stdin. Piped input continues after errors
    and exits with status one if any submission or command failed. Interactive
    errors leave the session usable; SIGINT retains its process-exit action. */
int repl_run(CliRequest request, ReplOptions options) {
  Frontend frontend = Frontend.new(request);
  if (!frontend.preload_macro_libraries()) return 1;
  ParsedUnit unit;
  int opened = frontend.open_session(&unit);
  defer unit.close();
  if (!opened) {
    foreach (Var entry, unit.compiler.diagnostics())
      unit.compiler.print_diagnostic(entry);
    return 1;
  }
  ReplSession session = ReplSession.new(unit.compiler);
  ReplInput input = ReplInput.new();
  defer input.close();
  String pending = "", line;
  struct ReplCompleteContext completion = { .session = session };
  int interactive = isatty(STDIN_FILENO), failed = 0;
  unit.compiler.macro_lisp.call_budget(1000000);
  MachineStats machine_stats = { 0 };
  unit.compiler.macro_lisp.auto_instrument(&machine_stats);
  defer unit.compiler.macro_lisp.auto_instrument(NULL);
  Pool stats_pool = Pool.current();
  ReplStatsSnapshot stats_baseline =
    _stats_snapshot(session, stats_pool, &machine_stats);
  if (interactive) puts("x2c experimental REPL; :help for commands");
  while (1) {
    if (interactive) {
      completion.pending = pending;
      ReplInputResult read = input.read(
        pending.len() ? "... " : "x2c> ",
        _complete_input, &completion);
      if (read.status == <cancelled>) {
        pending = "";
        continue;
      }
      if (read.status == <eof>) break;
      line = read.text;
    }
    else {
      line = Stdin.readline();
      if (!line) break;
    }
    String command = line.strip(NULL);
    if (interactive && command.startswith(":")) input.remember(command);
    if (command.startswith(":")) {
      size_t end = 0;
      while (end < command.len() && !_space(command[end])) end++;
      String operation = String.new_len(command, end);
      const struct ReplCommand *descriptor = _command(operation);
      if (!descriptor) {
        fprintf(stderr, "unknown command: %s\n", command);
        failed = 1;
      }
      else if (descriptor->argument == <none> &&
               command != descriptor->spelling) {
        fprintf(stderr, "usage: %s\n", descriptor->synopsis);
        failed = 1;
      }
      else if (descriptor->dispatch == <quit>) { pending = ""; break; }
      else if (descriptor->dispatch == <cancel>) pending = "";
      else if (descriptor->dispatch == <help>) _help();
      else if (descriptor->dispatch == <stats>) {
        int verbose;
        if (!_stats_mode(command, &verbose)) {
          fprintf(stderr, "usage: %s\n", descriptor->synopsis);
          failed = 1;
        }
        else _write_stats(
          Stdout, session, stats_pool, &machine_stats,
          stats_baseline, verbose);
      }
      else if (!_inspect(session, descriptor, command)) failed = 1;
      fflush(stdout);
      continue;
    }
    pending += line + "\n";
    ReplResult result = session.submit(pending);
    if (options.dump && result.syntax)
      fprintf(stderr, "typed: %%%s\n", result.syntax.repr());
    if (options.dump && result.lowered)
      fprintf(stderr, "lowered: %s\n", result.lowered.repr());
    $let(unit.compiler.text, result.source) {
      foreach (Var entry, result.diagnostics)
        unit.compiler.print_diagnostic(entry);
    }
    switch (result.status) {
      case <defined>: printf("defined %s\n", result.name); break;
      case <value>: printf("=> %s\n", result.value.repr()); break;
      case <executed>: puts("ok"); break;
      case <rejected>:
        failed = 1;
        if (result.message) fprintf(stderr, "rejected: %s\n", result.message);
        break;
      case <failed>:
        failed = 1;
        fprintf(stderr, "evaluation failed: %s\n", result.cause.repr());
        break;
    }
    if (result.status != <incomplete>) {
      if (interactive) input.remember(pending.remove_suffix("\n"));
      pending = "";
    }
    fflush(stdout);
  }
  if (options.stats || options.verbose_stats)
    _write_stats(
      Stderr, session, stats_pool, &machine_stats, stats_baseline,
      options.verbose_stats);
  if (pending.len()) { fputs("incomplete input at EOF\n", stderr); return 1; }
  return !interactive && failed;
}
