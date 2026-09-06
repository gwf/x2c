/*  lisp.x -- command-line shell for the x2c Lisp runtime */

#include <unistd.h>


static void _print_error(Symbol code, List detail) {
  List error = cons(Symbol.var(code), detail);
  Stderr.printf("error: %s\n", error.repr());
}

static int _eval_input(
  Lisp lisp, Var form, String source, int is_form, int print) {
  try {
    Var result = is_form ? Lisp.eval(lisp, form)
                         : Lisp.eval_string(lisp, source);
    if (print) Stdout.printf("%s\n", result.repr());
  }
  catch %(bad-arity *detail): {
    _print_error(<bad-arity>, detail);
    return 0;
  }
  catch %(bad-sig *detail): {
    _print_error(<bad-sig>, detail);
    return 0;
  }
  catch %(bad-types *detail): {
    _print_error(<bad-types>, detail);
    return 0;
  }
  catch %(not-call *detail): {
    _print_error(<not-call>, detail);
    return 0;
  }
  catch %(unbound *detail): {
    _print_error(<unbound>, detail);
    return 0;
  }
  catch %(malformed *detail): {
    _print_error(<malformed>, detail);
    return 0;
  }
  catch %(incomplete *detail): {
    _print_error(<incomplete>, detail);
    return 0;
  }
  catch %(not-found *detail): {
    _print_error(<not-found>, detail);
    return 0;
  }
  catch %(io-fail *detail): {
    _print_error(<io-fail>, detail);
    return 0;
  }
  catch %(no-symbol *detail): {
    _print_error(<no-symbol>, detail);
    return 0;
  }
  catch %(bad-result *detail): {
    _print_error(<bad-result>, detail);
    return 0;
  }
  catch %(void-op *detail): {
    _print_error(<void-op>, detail);
    return 0;
  }
  catch %(bad-arg *detail): {
    _print_error(<bad-arg>, detail);
    return 0;
  }
  catch %(bad-enc *detail): {
    _print_error(<bad-enc>, detail);
    return 0;
  }
  catch %(bad-op *detail): {
    _print_error(<bad-op>, detail);
    return 0;
  }
  catch %(bad-shift *detail): {
    _print_error(<bad-shift>, detail);
    return 0;
  }
  catch %(bad-target *detail): {
    _print_error(<bad-target>, detail);
    return 0;
  }
  catch %(conv-range *detail): {
    _print_error(<conv-range>, detail);
    return 0;
  }
  catch %(div-zero *detail): {
    _print_error(<div-zero>, detail);
    return 0;
  }
  catch %(no-convert *detail): {
    _print_error(<no-convert>, detail);
    return 0;
  }
  catch: {
    Stderr.puts("error: unknown failure\n");
    return 0;
  }
  return 1;
}

static int _eval_form(Lisp lisp, Var form) {
  return _eval_input(lisp, form, NULL, 1, 1);
}

static int _eval_text(Lisp lisp, String source, int print) {
  return _eval_input(lisp, void, source, 0, print);
}

static int _eval_file(Lisp lisp, const char *path, int print) {
  File input = NULL;
  int result = 0;
  try {
    input = File.open(path, "r");
    String source = input.string_close();
    result = _eval_text(lisp, source, print);
  }
  catch %(not-found *detail): {
    _print_error(<not-found>, detail);
    return 0;
  }
  catch %(io-fail *detail): {
    _print_error(<io-fail>, detail);
    return 0;
  }
  catch: {
    Stderr.puts("error: unknown failure\n");
    return 0;
  }
  return result;
}

static int _repl(Lisp lisp) {
  Buffer source = Buffer.new(0);
  unsigned cursor = 0;
  int failed = 0, incomplete = 0, interactive = isatty(Stdin.fileno());
  while (1) {
    if (interactive) {
      Stdout.puts(incomplete ? ".. " : "> ");
      Stdout.flush();
    }
    String line = NULL;
    try line = Stdin.readline();
    catch %(io-fail *detail): {
      _print_error(<io-fail>, detail);
      failed = 1;
      break;
    }
    catch: {
      Stderr.puts("error: unknown failure\n");
      failed = 1;
      break;
    }
    if (!line) {
      if (incomplete) {
        Stderr.puts("error: incomplete form at end of input\n");
        failed = 1;
      }
      break;
    }
    source.write(line);
    while (1) {
      Var form = void;
      Symbol status = 0;
      try {
        status = Lisp.read(lisp, source, &cursor, &form);
      }
      catch %(incomplete *): status = <incomplete>;
      catch %(malformed *detail): {
        _print_error(<malformed>, detail);
        status = <malformed>;
      }
      catch: {
        Stderr.puts("error: unknown failure\n");
        status = <malformed>;
      }
      if (status == <value>) {
        if (!_eval_form(lisp, form)) failed = 1;
        incomplete = 0;
        continue;
      }
      if (status == <incomplete>) {
        incomplete = 1;
        break;
      }
      if (status == <malformed>) {
        failed = 1;
      }
      source.clear();
      cursor = 0;
      incomplete = 0;
      break;
    }
  }
  source.free();
  return !failed;
}

static int _selftest(Lisp lisp) {
  int ok = _eval_text(lisp, "(apply + '(10 20 12))", 1);
  return _eval_text(lisp, "(append '(1 2) '(3 4))", 1) && ok;
}

static void _usage(const char *program) {
  Stderr.printf(
    "usage: %s [--init FILE] [--selftest | -e FORM | FILE]\n", program);
}

/* The default init file is at the repo root; probe upward from the
   current directory so the shell works from subdirectories too.
   Returns NULL when no candidate is readable. */
static const char *_default_init(char *buffer, size_t size) {
  char prefix[32] = "";
  for (int depth = 0; depth < 8; depth++) {
    snprintf(buffer, size, "%setc/init.xlisp", prefix);
    if (!access(buffer, R_OK)) return buffer;
    strcat(prefix, "../");
  }
  return NULL;
}

int main(int argc, char **argv) {
  Lisp lisp = Lisp.new_bare();
  const char *init = NULL;
  char probed[512];
  int arg = 1;
  if (argc >= 3 && !strcmp(argv[1], "--init")) {
    init = argv[2];
    arg = 3;
  }
  if (!init) init = getenv("X2C_LISP_INIT");
  if (!init) init = _default_init(probed, sizeof probed);
  if (!init) {
    Stderr.printf(
      "lisp: cannot find etc/init.xlisp; set X2C_LISP_INIT or --init\n"
    );
    Lisp.destroy(lisp);
    return 1;
  }
  int ok = _eval_file(lisp, init, 0);
  if (!ok) {
    Lisp.destroy(lisp);
    return 1;
  }
  int remaining = argc - arg;
  if (!remaining) ok = _repl(lisp);
  else if (remaining == 1 && !strcmp(argv[arg], "--selftest"))
    ok = _selftest(lisp);
  else if (remaining == 2 && !strcmp(argv[arg], "-e"))
    ok = _eval_text(lisp, String.new(argv[arg + 1]), 1);
  else if (remaining == 1) ok = _eval_file(lisp, argv[arg], 1);
  else {
    _usage(argv[0]);
    ok = 0;
  }
  Lisp.destroy(lisp);
  return ok ? 0 : 1;
}
