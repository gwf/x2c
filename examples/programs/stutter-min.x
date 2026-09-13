/* Minimal Stutter; the explained version is stutter.x.
   Copyright (c) 1997, 2026 Gary William Flake
   x2c build --output /tmp/stutter-min examples/programs/stutter-min.x
   /tmp/stutter-min [-heap CELLS] < examples/data/stutter.slp */
#include <unistd.h>
#include <errno.h>

enum { ATOM, LIST, FUNCTION, CAR, CDR, CONS, SET, EQUAL, QUOTE, LAMBDA, IF };
typedef struct Cell *Cell;
struct Cell { int kind, marked; Cell head, tail; String name; };
static inline Var Cell.var(Cell cell) => (Var) { .p64 = cell };
static inline Cell Var.cell(Var value) => value.p64;
protocol Var(Cell);
static Cell _heap, _free, _nil, _truth, _error, _quote;
static int _capacity = 10240;
static Map _atoms = %{};
static Array _roots = %[];
static char _line[256], *_cursor;

static Cell _hold(Cell cell) => _roots.push(cell);
static Cell _fail(const char *message) {
  Stdout.puts(message); return _error;
}
static void _mark(Cell cell) {
  while (cell && !cell.marked) {
    cell.marked = 1; _mark(cell.head); cell = cell.tail;
  }
}
static Cell _new(int kind, Cell head, Cell tail) {
  if (!_free) {
    Stderr.puts("Garbage collecting..."); Stderr.flush();
    _mark(head); _mark(tail);
    foreach (Cell atom, _atoms) _mark(atom);
    foreach (Cell root, _roots) _mark(root);
    int count = 0;
    for (int i = 0; i < _capacity; i++) {
      Cell cell = _heap + i;
      if (!cell.marked) { cell.head = _free; _free = cell; count++; }
      cell.marked = 0;
    }
    if (!count) {
      Stderr.puts("\nGarbage collection failed!\n"); exit(1);
    }
    Stderr.printf("harvested %d cells.\n", count);
  }
  Cell cell = _free;
  _free = cell.head;
  *cell = (struct Cell) { .kind = kind, .head = head, .tail = tail };
  return cell;
}
static Cell _atom(String name) {
  if (name in _atoms) return _atoms[name];
  Cell atom = _new(ATOM, NULL, NULL);
  atom.name = name; _atoms[name] = atom;
  return atom;
}
static Cell _part(Cell cell, int tail) {
  if (!cell || cell == _nil) return _nil;
  if (cell == _error) return cell;
  if (cell.kind == LIST) return tail ? cell.tail : cell.head;
  Stdout.printf("Error: %s: argument is not a list.", tail ? "cdr" : "car");
  return _error;
}
static Cell _cons(Cell head, Cell tail) {
  if (head == _error || tail == _error) return _error;
  if (tail != _nil && (!tail || tail.kind != LIST))
    return _fail("Error: cons: second argument is not a list.");
  return _new(LIST, head, tail);
}
static String _token(int consume) {
  while (1) {
    if (!_cursor || !*_cursor || strchr("\n;", *_cursor)) {
      if (!(_cursor = fgets(_line, sizeof(_line), stdin))) return NULL;
    }
    else if (strchr(" \t", *_cursor)) _cursor++;
    else {
      char *start = _cursor, *end = start + 1;
      if (!strchr("()'", *start))
        while (*end && !strchr("()' \t\n;", *end)) end++;
      if (consume) _cursor = end;
      return String.new_len(start, end - start);
    }
  }
}
static Cell _read(void) {
  String token = _token(1);
  if (!token) return NULL;
  if (token == "'") return _cons(_quote, _cons(_read(), _nil));
  if (token == ")") {
    _cursor = NULL; return _fail("parse error: unexpected ')'\n");
  }
  if (token != "(") return _atom(token);
  int base = _roots.len();
  defer _roots.truncate(base);
  while ((token = _token(0)) && token != ")")
    if (_hold(_read()) == _error) return _error;
  if (!token) return _fail("parse error: unexpected EOF.\n");
  _token(1);
  Cell list = _nil;
  for (int i = _roots.len() - 1; i >= base; i--)
    list = _cons(_roots[i], list);
  return list;
}
static Cell _invoke(Cell fn, Cell args) {
  int base = _roots.len();
  defer _roots.truncate(base);
  for (Cell p = fn.head; p != _nil; p = p.tail) {
    Cell value = args == _nil ? _nil : _eval(args.head);
    if (value == _error) return value;
    _hold(p.head); _hold(value); _hold(NULL);
    if (args != _nil) args = args.tail;
  }
  // Save after evaluating all actuals; reverse binding makes first win.
  int end = _roots.len();
  for (int i = end - 3; i >= base; i -= 3) {
    Cell name = _roots[i];
    _roots[i+2] = name.head; name.head = _roots[i+1];
  }
  defer for (int i = base; i < end; i += 3) {
    Cell name = _roots[i]; name.head = _roots[i+2];
  }
  return _eval(fn.tail);
}
static Cell _eval(Cell form) {
  if (!form || form == _error) return form;
  if (form.kind == ATOM) {
    if (form.head) return form.head;
    Stdout.printf("Error: unbound atom \"%s\".", form.name); return _error;
  }
  if (form.kind != LIST) return form;
  int base = _roots.len();
  _hold(form);
  defer _roots.truncate(base);
  Cell fn = _hold(_eval(form.head)), args = form.tail;
  if (fn == _error) return fn;
  if (!fn || fn.kind < FUNCTION) return form;
  if (fn.kind == FUNCTION) return _invoke(fn, args);
  Cell a = _part(args, 0), b = _part(_part(args, 1), 0);
  if (fn.kind <= EQUAL) { a = _hold(_eval(a)); b = _eval(b); }
  switch (fn.kind) {
    case CAR: case CDR: return _part(a, fn.kind == CDR);
    case CONS: return _cons(a, b);
    case SET:
      if (a == _error || b == _error) return _error;
      if (!a || a.kind != ATOM)
        return _fail("Error: set: first argument is not an atom.");
      return a.head = b;
    case EQUAL: return a && a.kind == ATOM && a == b ? _truth : _nil;
    case QUOTE: return a;
    case IF:
      return _eval(_eval(a) != _nil ? b : _part(_part(_part(args, 1), 1), 0));
    case LAMBDA:
      if (a != _nil && (!a || a.kind != LIST))
        return _fail("Error: bad argument list supplied.");
      for (Cell p = a; p != _nil; p = p.tail)
        if (!p.head || p.head.kind != ATOM)
          return _fail("Error: bad argument list supplied.");
      return _new(FUNCTION, a, b);
  }
  return form;
}
static void _print(Cell cell) {
  if (!cell) Stdout.puts("<NULL>");
  else if (cell == _error) return;
  else if (cell.kind == ATOM) Stdout.puts(cell.name);
  else if (cell.kind >= CAR)
    Stdout.puts(cell.kind <= EQUAL ? "<internal-value-function>" :
                                   "<internal-special-function>");
  else {
    Stdout.puts(cell.kind == LIST ? "(" : "(lambda ");
    _print(cell.head);
    if (cell.kind == FUNCTION) { Stdout.puts(" "); _print(cell.tail); }
    else for (cell = cell.tail; cell != _nil; cell = cell.tail) {
      Stdout.puts(" "); _print(cell.head);
    }
    Stdout.puts(")");
  }
}
static int _usage(const char *program) {
  Stderr.printf("Usage: %s [ options ]\n\n", program);
  Stderr.puts("    Stutter understands car, cdr, cons, if, set, equal,\n"
              "    quote, and lambda. Programs use atoms and proper lists,\n"
              "    dynamically scoped functions, and a mark-and-sweep heap.\n"
              "    Read expressions from standard input.\n\n"
              "Options with defaults in parentheses are:\n\n");
  Stderr.printf("    -heap  Number of cells in the heap. (%d)\n\n", _capacity);
  return 1;
}
int main(int argc, char **argv) {
  for (int i = 1; i < argc; i++) {
    String option = argv[i];
    if (option == "-help") return _usage(argv[0]);
    if (option != "-heap" || i + 1 == argc) {
      Stderr.printf("%s: unknown or incorrectly used option \"%s\".\n",
                    argv[0], argv[i]);
      return _usage(argv[0]);
    }
    char *end;
    errno = 0;
    long size = strtol(argv[++i], &end, 10);
    if (errno || *end || end == argv[i] || size <= 0 || size > INT_MAX) {
      Stderr.puts("Error: -heap requires a positive cell count.\n"); return 1;
    }
    _capacity = size;
  }
  $scope() {
    _heap = Scope.calloc(_capacity, sizeof(struct Cell));
    for (int i = _capacity - 1; i >= 0; i--) {
      Cell cell = _heap + i; cell.head = _free; _free = cell;
    }
    _nil = _atom("nil"); _nil.head = _nil;
    _truth = _atom("t"); _truth.head = _truth;
    _error = _atom("<error>"); _error.head = _error;
    int kind = CAR;
    foreach (Symbol op, %(car cdr cons set equal quote lambda if)) {
      Cell atom = _atom(op.str());
      atom.head = _new(kind++, NULL, NULL);
    }
    _quote = _atom("quote");
    while (1) {
      Stdout.puts("> "); Stdout.flush();
      Cell form = _read();
      if (!form) break;
      if (!isatty(STDIN_FILENO)) { _print(form); Stdout.puts("\n"); }
      _print(_eval(form)); Stdout.puts("\n");
    }
    Stdout.puts("\n");
  }
  return 0;
}
