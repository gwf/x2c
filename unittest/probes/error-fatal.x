/*  error-fatal.x -- process-isolated terminal error-floor probes */

#include "x2c.x"

#include <stdint.h>
#include <string.h>

static Symbol _consume_terminal(List errors, Var data) {
  (void) errors;
  (void) data;
  return <handled>;
}

static void _raise_during_shutdown(void) {
  fprintf(stderr, "shutdown-hook: before raise\n");
  raise %(late-probe (phase late-hook));
  fprintf(stderr, "shutdown-hook: after raise\n");
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  Symbol code = <abort-prob>;
  List detail = NULL;

  if (!strcmp(argv[1], "abort-policy")) {
    Error.initialize();
    x2c_error_raise(code, detail);
  }
  if (!strcmp(argv[1], "uncaught-invariant")) {
    Error.initialize();
    x2c_error_raise(<invariant>, detail);
  }
  if (!strcmp(argv[1], "uncaught-format")) {
    Error.initialize();
    x2c_error_raise(<format>, detail);
  }
  if (!strcmp(argv[1], "uncaught-not-found")) {
    Error.initialize();
    x2c_error_raise(<not-found>, detail);
  }
  if (!strcmp(argv[1], "uncaught-malformed")) {
    Error.initialize();
    x2c_error_raise(<malformed>, detail);
  }
  if (!strcmp(argv[1], "after-shutdown")) {
    Error.initialize();
    Error.shutdown();
    x2c_error_raise(code, detail);
  }
  if (!strcmp(argv[1], "handled-alloc") ||
      !strcmp(argv[1], "handled-size") ||
      !strcmp(argv[1], "handled-format") ||
      !strcmp(argv[1], "handled-io-fail") ||
      !strcmp(argv[1], "handled-bad-arity") ||
      !strcmp(argv[1], "handled-invariant")) {
    Error.initialize();
    Error.push(_consume_terminal, void);
    Symbol terminal = !strcmp(argv[1], "handled-alloc") ? <alloc-fail>
                    : !strcmp(argv[1], "handled-size") ? <size-limit>
                    : !strcmp(argv[1], "handled-format") ? <format>
                    : !strcmp(argv[1], "handled-io-fail") ? <io-fail>
                    : !strcmp(argv[1], "handled-bad-arity") ? <bad-arity>
                    : <invariant>;
    Error.raise(terminal, detail);
  }
  if (!strcmp(argv[1], "pool-isolation")) {
    Error.initialize();
    Pool transient = String.pool_retain_named("error-floor-transfer");
    String text = String.new("ephemeral error detail");
    Block records = transient.up.table.entries.block();
    records.width = SIZE_MAX;
    records.cap = records.length;
    try {
      raise %(bad-arg (text $text));
    }
    catch %(bad-arg *): return 0;
    return 1;
  }
  if (!strcmp(argv[1], "dynamic-invalid")) {
    Error.initialize();
    Array mutable = %[1];
    List invalid = %((value $mutable));
    Error.raise(<bad-types>, invalid);
  }
  if (!strcmp(argv[1], "context-bound")) {
    Error.initialize();
    Error.bound_set(100);
    Context context = Context.open();
    Error.bound_set(1);
    Error.policy_set(<bound-prob>, <collect>);
    Error.raise(<bound-prob>, %((sequence 1)));
    Error.raise(<bound-prob>, %((sequence 2)));
    context.close();
    return 0;
  }
  if (!strcmp(argv[1], "shutdown-order")) {
    Logger.initialize();
    Error.policy_set(<hook-probe>, <collect>);
    Error.policy_set(<late-probe>, <collect>);
    raise %(hook-probe (phase root));
    Scope.shutdown_hook(_raise_during_shutdown);
    Scope_shutdown();
    fprintf(stderr, "shutdown-complete: error-ready=%d\n", Error.ready());
    return Error.ready() ? 1 : 0;
  }
  return 2;
}
