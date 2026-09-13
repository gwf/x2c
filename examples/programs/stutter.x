/*  stutter.x -- the book's eight-primitive Lisp, written in x2c

    Copyright (c) 1997, 2026 Gary William Flake

    Build: x2c build --output /tmp/stutter examples/programs/stutter.x
    Run:   /tmp/stutter [-heap CELLS] < program.slp

    Stutter has atoms, proper lists, and dynamically scoped functions.
    Numbers are names: the book's programs build arithmetic from lists.
    This interpreter supplies its own reader, evaluator, and collector;
    it uses no x2c Lisp interpreter, reader, or standard library.

    Maps replace the C version's association lists. The heap still bounds
    live cells, but binding storage no longer consumes Lisp cells, so the
    same -heap setting need not collect at the same time. Collection is
    mark-and-sweep, as in stutter.c (despite its old help text).
*/

#include <unistd.h>
#include <errno.h>

/* Cells retain their addresses until collected. The two edges hold a
   list's head/tail, a lambda's parameters/body, or an atom's global value.
   Builtins use their operation name as the kind. Strings and Maps belong
   to the session Scope; the collector owns only the cell array.
*/
typedef struct Cell *Cell;
struct Cell {
  Symbol kind;
  Cell head, tail;
  String name;
  int marked;
};

static inline Var Cell.var(Cell cell) => (Var) { .p64 = cell };
static inline Cell Var.cell(Var value) => value.p64;
protocol Var(Cell);

typedef struct Env {
  Map bindings;
  struct Env *parent;
} Env;

typedef struct Reader {
  char line[256];
  char *cursor;
} Reader;

typedef struct Stutter {
  Cell heap, free, nil, truth, error, quote;
  int capacity;
  Map atoms;
  Array roots;
  Env *env;
  Reader reader;
} Stutter;

/* Explicit roots keep native temporaries alive across allocating calls.
   Constructor arguments are roots too. Following the tail in a loop
   avoids consuming the native stack for every element of a flat list.
*/
static void Cell.mark(Cell cell) {
  while (cell && !cell.marked) {
    cell.marked = 1;
    cell.head.mark();
    cell = cell.tail;
  }
}

static void Stutter.collect(Stutter *self, Cell head, Cell tail) {
  Stderr.puts("Garbage collecting...");
  Stderr.flush();
  head.mark();
  tail.mark();
  foreach (Cell atom, self.atoms) atom.mark();
  foreach (Cell root, self.roots) root.mark();
  for (Env *env = self.env; env; env = env.parent)
    foreach (Cell value, env.bindings) value.mark();
  int count = 0;
  for (int i = 0; i < self.capacity; i++) {
    Cell cell = self.heap + i;
    if (!cell.marked) {
      cell.head = self.free;
      self.free = cell;
      count++;
    }
    cell.marked = 0;
  }
  if (!count) {
    Stderr.puts("\nGarbage collection failed!\n");
    exit(1);
  }
  Stderr.printf("harvested %d cells.\n", count);
}

static Cell Stutter.cell(
  Stutter *self, Symbol kind, Cell head, Cell tail) {
  if (!self.free) self.collect(head, tail);
  Cell cell = self.free;
  self.free = cell.head;
  *cell = (struct Cell) { .kind = kind, .head = head, .tail = tail };
  return cell;
}

static Cell Stutter.atom(Stutter *self, String name) {
  if (name in self.atoms) return self.atoms[name];
  Cell atom = self.cell(<atom>, NULL, NULL);
  atom.name = name;
  self.atoms[name] = atom;
  return atom;
}

static Cell Stutter.fail(Stutter *self, const char *message) {
  Stdout.puts(message);
  return self.error;
}

/* A null pointer denotes absent input or an unbound value. Lisp's nil is
   an interned atom, also used for the empty list and the only false value.
   Keeping those identities separate allows nil itself to be rebound.
*/
static Cell Stutter.car(Stutter *self, Cell cell) {
  if (!cell || cell == self.nil) return self.nil;
  if (cell == self.error) return cell;
  if (cell.kind != <list>)
    return self.fail("Error: car: argument is not a list.");
  return cell.head;
}

static Cell Stutter.cdr(Stutter *self, Cell cell) {
  if (!cell || cell == self.nil) return self.nil;
  if (cell == self.error) return cell;
  if (cell.kind != <list>)
    return self.fail("Error: cdr: argument is not a list.");
  return cell.tail;
}

static Cell Stutter.cons(Stutter *self, Cell head, Cell tail) {
  if (head == self.error || tail == self.error) return self.error;
  if (tail != self.nil && (!tail || tail.kind != <list>))
    return self.fail("Error: cons: second argument is not a list.");
  return self.cell(<list>, head, tail);
}

static Cell Stutter.set(Stutter *self, Cell name, Cell value) {
  if (name == self.error || value == self.error) return self.error;
  if (!name || name.kind != <atom>)
    return self.fail("Error: set: first argument is not an atom.");
  for (Env *env = self.env; env; env = env.parent)
    if (name in env.bindings) {
      env.bindings[name] = value;
      return value;
    }
  return name.head = value;
}

static Cell Stutter.lookup(Stutter *self, Cell atom) {
  for (Env *env = self.env; env; env = env.parent)
    if (atom in env.bindings) return env.bindings[atom];
  if (atom.head) return atom.head;
  Stdout.printf("Error: unbound atom \"%s\".", atom.name);
  return self.error;
}

/* The original scanner reads 255-byte chunks. Only ()', space, tab,
   newline, and semicolon have syntax; quotes, dots, and digits in a token
   are ordinary name characters. A semicolon skips the current chunk.
*/
static String Reader.token(Reader *self, int consume) {
  while (1) {
    if (!self.cursor || !*self.cursor || *self.cursor == '\n' ||
        *self.cursor == ';') {
      self.cursor = fgets(self.line, sizeof(self.line), stdin);
      if (!self.cursor) return NULL;
      continue;
    }
    if (*self.cursor == ' ' || *self.cursor == '\t') {
      self.cursor++;
      continue;
    }
    char *start = self.cursor, *end = start + 1;
    if (!strchr("()'", *start))
      while (*end && !strchr("()' \t\n;", *end)) end++;
    if (consume) self.cursor = end;
    return String.new_len(start, end - start);
  }
}

static Cell Stutter.read_list(Stutter *self) {
  int base = self.roots.len();
  defer self.roots.truncate(base);
  while (1) {
    String next = self.reader.token(0);
    if (!next) return self.fail("parse error: unexpected EOF.\n");
    if (next == ")") {
      self.reader.token(1);
      Cell list = self.nil;
      for (int i = self.roots.len() - 1; i >= base; i--)
        list = self.cons(self.roots[i], list);
      return list;
    }
    Cell item = self.read();
    if (item == self.error) return item;
    self.roots.push(item);
  }
}

static Cell Stutter.read(Stutter *self) {
  String token = self.reader.token(1);
  if (!token) return NULL;
  if (token == "(") return self.read_list();
  if (token == "'") {
    Cell item = self.read();
    return self.cons(self.quote, self.cons(item, self.nil));
  }
  if (token == ")") {
    self.reader.cursor = NULL;
    return self.fail("parse error: unexpected ')'\n");
  }
  return self.atom(token);
}

/* Lambdas capture no environment. Evaluate actual arguments in the caller
   before installing the frame, then restore the caller on return. Missing
   arguments are nil; extras are never evaluated; the first repeated formal
   wins. set updates the nearest frame that contains its name.
*/
static Cell Stutter.invoke(Stutter *self, Cell fn, Cell args) {
  Map bindings = $auto(%{});
  Env local = { bindings, self.env };
  int base = self.roots.len();
  defer self.roots.truncate(base);
  for (Cell params = fn.head; params != self.nil; params = params.tail) {
    Cell value = args == self.nil ? self.nil : self.eval(args.head);
    if (value == self.error) return value;
    self.roots.push(value);
    if (!(params.head in bindings)) bindings[params.head] = value;
    if (args != self.nil) args = args.tail;
  }
  self.env = &local;
  defer self.env = local.parent;
  return self.eval(fn.tail);
}

static Cell Stutter.special(Stutter *self, Symbol op, Cell args) {
  Cell first = self.car(args);
  if (op == <quote>) return first;
  Cell second = self.car(self.cdr(args));
  if (op == <if>) {
    Cell third = self.car(self.cdr(self.cdr(args)));
    // The reference treats its error sentinel as true, after printing it.
    return self.eval(self.eval(first) != self.nil ? second : third);
  }
  if (first != self.nil && (!first || first.kind != <list>))
    return self.fail("Error: bad argument list supplied.");
  for (Cell params = first; params != self.nil; params = params.tail)
    if (!params.head || params.head.kind != <atom>)
      return self.fail("Error: bad argument list supplied.");
  return self.cell(<user-fn>, first, second);
}

static const SymbolSet _values = %<<car cdr cons set equal>>;
static const SymbolSet _specials = %<<quote lambda if>>;

static Cell Stutter.eval(Stutter *self, Cell form) {
  if (!form || form == self.error) return form;
  if (form.kind == <atom>) return self.lookup(form);
  if (form.kind != <list>) return form;
  int base = self.roots.len();
  self.roots.push(form);
  defer self.roots.truncate(base);
  Cell fn = self.eval(form.head), args = form.tail;
  if (fn == self.error) return fn;
  self.roots.push(fn);
  if (fn && fn.kind == <user-fn>) return self.invoke(fn, args);
  if (fn && _specials.contains(fn.kind)) return self.special(fn.kind, args);
  if (fn && _values.contains(fn.kind)) {
    // Even car and cdr evaluate two arguments. Extras are ignored.
    Cell a = self.eval(self.car(args));
    self.roots.push(a);
    Cell b = self.eval(self.car(self.cdr(args)));
    switch (fn.kind) {
      case <car>: return self.car(a);
      case <cdr>: return self.cdr(a);
      case <cons>: return self.cons(a, b);
      case <set>: return self.set(a, b);
      case <equal>:
        return a && a.kind == <atom> && a == b ? self.truth : self.nil;
    }
  }
  return form;
}

/* Printing preserves Stutter's transcript: nil for (), expanded quotation,
   readable lambdas, and no text for the error sentinel. Lists are never
   compared structurally by equal, even when their printed forms coincide.
*/
static void Stutter.print(Stutter *self, Cell cell) {
  if (!cell) Stdout.puts("<NULL>");
  else if (cell == self.error) return;
  else if (cell.kind == <atom>) Stdout.puts(cell.name);
  else if (cell.kind == <user-fn>) {
    Stdout.puts("(lambda ");
    self.print(cell.head);
    Stdout.puts(" ");
    self.print(cell.tail);
    Stdout.puts(")");
  }
  else if (cell.kind == <list>) {
    Stdout.puts("(");
    while (cell != self.nil) {
      self.print(cell.head);
      cell = cell.tail;
      if (cell != self.nil) Stdout.puts(" ");
    }
    Stdout.puts(")");
  }
  else Stdout.puts(_values.contains(cell.kind) ? "<internal-value-function>" :
                   "<internal-special-function>");
}

static Stutter Stutter.new(int capacity) {
  Stutter self = { .capacity = capacity, .atoms = %{}, .roots = %[],
                   .heap = Scope.calloc(capacity, sizeof(struct Cell)) };
  for (int i = capacity - 1; i >= 0; i--) {
    Cell cell = self.heap + i;
    cell.head = self.free;
    self.free = cell;
  }
  self.nil = self.atom("nil");
  self.nil.head = self.nil;
  self.truth = self.atom("t");
  self.truth.head = self.truth;
  self.error = self.atom("<error>");
  self.error.head = self.error;
  foreach (Symbol op, %(car cdr cons set equal quote lambda if)) {
    Cell atom = self.atom(op.str());
    atom.head = self.cell(op, NULL, NULL);
  }
  self.quote = self.atom("quote");
  return self;
}

static int _usage(const char *program, int capacity) {
  Stderr.printf("Usage: %s [ options ]\n\n", program);
  Stderr.puts("    Stutter understands car, cdr, cons, if, set, equal,\n"
              "    quote, and lambda. Programs use atoms and proper lists,\n"
              "    dynamically scoped functions, and a mark-and-sweep heap.\n"
              "    Read expressions from standard input.\n\n"
              "Options with defaults in parentheses are:\n\n");
  Stderr.printf("    -heap  Number of cells in the heap. (%d)\n\n", capacity);
  return 1;
}

int main(int argc, char **argv) {
  int capacity = 10240;
  for (int i = 1; i < argc; i++) {
    String option = argv[i];
    if (option == "-help") return _usage(argv[0], capacity);
    if (option != "-heap" || i + 1 == argc) {
      Stderr.printf("%s: unknown or incorrectly used option \"%s\".\n",
                    argv[0], argv[i]);
      return _usage(argv[0], capacity);
    }
    char *end;
    errno = 0;
    long size = strtol(argv[++i], &end, 10);
    if (errno || *end || end == argv[i] || size <= 0 || size > INT_MAX) {
      Stderr.puts("Error: -heap requires a positive cell count.\n");
      return 1;
    }
    capacity = size;
  }
  $scope() {
    Stutter self = Stutter.new(capacity);
    while (1) {
      Stdout.puts("> ");
      Stdout.flush();
      Cell form = self.read();
      if (!form) break;
      if (!isatty(STDIN_FILENO)) {
        self.print(form);
        Stdout.puts("\n");
      }
      self.print(self.eval(form));
      Stdout.puts("\n");
    }
    Stdout.puts("\n");
  }
  return 0;
}
