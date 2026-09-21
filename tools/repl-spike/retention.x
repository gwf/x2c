/*  retention.x -- measure storage while an incremental session stays open

    Copyright (c) 2026 Gary William Flake.
*/
#include "session.x"
#include "scope.x"
#include "pool.x"
#include "lisp.x"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>

static long _peak_bytes(void) {
  struct rusage usage;
  getrusage(RUSAGE_SELF, &usage);
#ifdef __APPLE__
  return usage.ru_maxrss;
#else
  return usage.ru_maxrss * 1024;
#endif
}

static double _seconds(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return now.tv_sec + now.tv_nsec / 1000000000.0;
}

static void _sample(String mode, int count, double started) {
  ScopeStats scope = Scope.stats();
  PoolStats pool = Pool.stats(Pool.current());
  printf("%s,%d,%.6f,%zu,%zu,%zu,%zu,%ld\n", mode, count,
         _seconds() - started, scope.live_allocations, scope.requested_bytes,
         pool.interned, pool.active_bytes, _peak_bytes());
  fflush(stdout);
}

int main(int argc, char **argv) {
  if (argc != 4) return 2;
  x2c_initialize_environment(argv[0]);
  String mode = String.new(argv[2]);
  int limit = atoi(argv[3]);
  if (limit <= 0) return 2;
  if (mode != "fixed" && mode != "values" && mode != "functions" &&
      mode != "rejected" && mode != "incomplete" && mode != "evaluate" &&
      mode != "transaction" && mode != "lisp")
    return 2;
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest));
  request.command = <translate>;
  Frontend frontend = Frontend.new(request);
  if (!frontend.preload_macro_libraries()) return 1;
  ParsedUnit unit;
  if (!frontend.open(String.new(argv[1]), &unit)) return 1;
  defer unit.close();
  ReplSession session = ReplSession.new(unit.compiler);
  if (session.submit("int n=0;").status != <executed>) return 1;
  if (mode == "lisp" && session.submit(
      "int tick(void) { n+=1; return n; }").status != <defined>) return 1;
  double started = _seconds();
  puts("mode,count,seconds,live_allocations,requested_bytes,interned,"
       "pool_active_bytes,peak_rss_bytes");
  _sample(mode, 0, started);
  for (int i = 1; i <= limit; i++) {
    String source = "n += 1;";
    Symbol expected = <executed>;
    if (mode == "values") source = %"int value_$i = $i;";
    else if (mode == "functions") {
      source = %"int function_$i(void) { return $i; }";
      expected = <defined>;
    }
    else if (mode == "rejected") {
      source = "int broken = ;";
      expected = <rejected>;
    }
    else if (mode == "incomplete") {
      source = "int broken(int x,";
      expected = <incomplete>;
    }
    else if (mode == "evaluate") {
      source = "n + 1;";
      expected = <value>;
    }
    ReplResult result = { .status = <executed> };
    if (mode == "transaction") {
      Scope scratch = Scope.new();
      SymTxn transaction;
      {
        Scope.push(&scratch);
        defer Scope.pop();
        transaction = unit.compiler.begin_semantic_transaction();
      }
      transaction.rollback();
      scratch.destroy();
    }
    else if (mode == "lisp") (void) unit.compiler.macro_lisp.eval(%(tick));
    else result = session.submit(source);
    if (result.status != expected) {
      fprintf(stderr, "unexpected result at input %d: %s\n", i,
              result.status.str());
      return 1;
    }
    if (i % 100 == 0 || i == limit) _sample(mode, i, started);
    if (_peak_bytes() > 512L * 1024 * 1024) {
      fputs("stopped at 512 MiB peak resident storage\n", stderr);
      return 3;
    }
  }
  String final_source = "n;";
  if (mode == "values") final_source = %"value_$limit;";
  else if (mode == "functions") final_source = %"function_$limit();";
  int want = mode == "fixed" || mode == "values" || mode == "functions" ||
    mode == "lisp"
    ? limit : 0;
  ReplResult final = session.submit(final_source);
  return final.status != <value> || final.value != want;
}
