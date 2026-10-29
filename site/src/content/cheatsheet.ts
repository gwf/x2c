// The one-page cheat sheet: four columns of sections, each a list of
// [code, note] rows. Notes may mark inline code with backticks.

export interface Section {
  column: 1 | 2 | 3 | 4;
  title: string;
  rows: [string, string][];
}

export const sheet: Section[] = [
  { column: 1, title: "Start", rows: [
    ["hello.x", "Any C file is a unit: one `.c`, one `.h`."],
    ["x2c run hello.x -- args", "Build and run; `--` starts the arguments."],
    ["x2c build -o app a.x b.x", "An executable. `translate` emits C only."],
    ["#include \"unit.x\"", "Its public names; `static` keeps one private."],
    ["import \"pcre2\" as rx;", "A package under an alias: `rx.Regexp`."],
    ["#!/usr/bin/env -S x2c script", "A script: file-scope statements run."],
  ] },
  { column: 1, title: "Values", rows: [
    ["Var v = 42;", "One tagged word holds anything; `v is int`."],
    ["int n = v;  (long) v", "A typed destination converts; `v.str()`."],
    ["\"text\"  %\"a $x $(f(y))\"", "`String`: immutable, canonical; `%\"\"` interpolates."],
    ["s[1:3]  s.len()  s + t", "`split strip lower upper words lines replace`."],
    ["<name>", "`Symbol`: a constant; `%<<a b c>>` is an ordered set."],
    ["%(1 2 (3) \"s\" $x @xs)", "`List`: immutable, shared; `$x` inserts, `@xs` splices."],
    ["cons(0, xs)  xs.car()  xs.cdr()", "`map filter foldl last assoc repr`."],
    ["[1, 2, 3]  a.push(4)  a[-1]", "`Array`: mutable, has identity; `pop sort copy`."],
    ["{key: 1, \"s\": 2}  m[<key>]", "`Map`: bare keys are Symbols; `getdefault try_get del`."],
    ["$(a, b)  ${k: v}", "Evaluated `List` and `Map`."],
    ["== vs ===  x in c", "Content, identity, membership."],
    ["void  NULL  nil  \"\"", "Four absences; a missing key reads as `void`."],
  ] },
  { column: 1, title: "Functions", rows: [
    ["int f(int x) => x * 2;", "Expression body; define after use is fine."],
    ["%!(a, b) => a + b", "A lambda; `using &k` captures by reference."],
    ["Func g = f;  g(21)", "First-class; results through `Func` are `Var`."],
    ["T f(String s, Map @opts)", "Keyword arguments: `f(\"x\", port: 80)`."],
    ["T f(List @rest)", "Rest arguments as a `List`."],
    ["void bump(int &n)", "Reference parameter; call `bump(n)`. `&?p` allows `NULL`."],
  ] },

  { column: 2, title: "Flow", rows: [
    ["foreach (T x in c)", "Collections, a `File` by line, a `Channel`."],
    ["foreach ((k, v) in map)", "Unpack pairs; `(int a, int b) = list;` destructures."],
    ["match (x) { case %(tag ?a *r): ... }", "By shape: `?a` one, `*r` rest, `?` skip."],
    ["case %(p ?a) if (a > 0):", "A guard. `default:` for the rest; no fall-through."],
    ["if (x ~= %(pair ?(int a) ?b))", "A pattern condition binds where it holds."],
    ["switch (s) { case \"get\": }", "A `switch` on a `String` selects by content."],
    ["with (n = 5) { ... }", "Assign for the block, restore on every exit."],
    ["alias total to a + b;", "Name an expression; each use re-evaluates it."],
    ["defer f.close();", "Runs at block exit, on `return`, and on a raise."],
    ["a[start:stop:step]", "Slices; negatives count from the end."],
  ] },
  { column: 2, title: "Memory", rows: [
    ["auto { ... }", "A region, freed at exit; no `free`."],
    ["for (...) auto { ... }", "One region per iteration."],
    ["T t = auto T.new();", "Clean up this value at block exit."],
    ["Scope.retain(); defer Scope.release();", "The same region by hand."],
    ["xmalloc(n)  xfree(p)", "Scope-owned C allocation."],
  ] },
  { column: 2, title: "Errors", rows: [
    ["raise %(bad-arg (reason \"r\"));", "An `Error` is a `List`: cause, then details."],
    ["try stmt catch %(not-found *): stmt", "By pattern; `catch %(?c *d):` binds the rest."],
    ["catch: stmt   finally stmt", "Anything else; cleanup after the handlers."],
    ["uncaught <no-convert> in main (f.x:3)", "Runtime failures name your line."],
  ] },

  { column: 2, title: "Lisp", rows: [
    ["Lisp l = Lisp.new();", "An interpreter inside; `defer l.destroy();`."],
    ["$lisp.bind(l, \"name\", fn);", "Expose a native function."],
    ["l.eval(%(f 1 2))  l.eval_string(s)", "Code is a `List`; results convert."],
  ] },

  { column: 3, title: "Types", rows: [
    ["int T.f(T self, int n)", "A dotted method; `value.f(3)` passes the receiver."],
    ["class Point { int x; int y; };", "A value class: `new`, `==`, hash, `repr` come free."],
    ["class Node { int v; } *;", "A pointer class, allocated in the Scope."],
    ["void T.init(T t, ...)  T.drop", "`init drop repr equal hash` replace the defaults."],
    ["delegate T field;", "Forward unknown dotted calls through a field."],
    ["protocol Base(T) { long T.m(T); }", "A contract, named for its base type."],
    ["protocol Base(Impl);", "Adopt it on purpose; override any method."],
    ["T.add T.mul T.equal T.getindex T.str", "Give `+ * == [] %s`; also `sub div compare`."],
    ["$derive(T, <json>, <equal>, <repr>)", "Methods from the fields; `<map> <args> <row>` too."],
    ["ArrayInt  ListInt  MapIntInt", "Unboxed families from `typed-*.x`."],
  ] },
  { column: 3, title: "Concurrency", rows: [
    ["Thread.run([%!(void) => {...}, ...])", "Start every worker, join them all."],
    ["Thread.start(fn, v)  t.join()", "One thread; `join` returns a `Var`."],
    ["Channel.new(<i32>, 2)", "Typed, bounded; `send close`, `foreach` drains."],
    ["$lock(m) { ... }", "Hold a `Mutex` for one block."],
    ["threaded int counter;", "Thread-local storage."],
  ] },
  { column: 3, title: "Compile time", rows: [
    ["macro Expression $m(Expr $e) => $e * 60;", "A typed template; `$m(2)` expands it. `Code.type($e)` asks the compiler."],
    ["macro Stmt $s(Expr $a, Expr $b) { ... }", "Hygienic names; `using name` keeps one."],
    ["macro Decorator $d(Function $f) { @Code.body($f) }", "Wraps the item after `$d()`."],
    ["keyword repeat $ns.repeat;", "`repeat (3) stmt` is now syntax here."],
    ["meta int f(int n) => ...;", "`$f(3)` runs inside the compiler."],
    ["$!( { @items } )  $!Stmt{ ... }", "Quote code; `$x` inserts, `@xs` splices."],
    ["meta List g(TypeInfo t)", "Gets `(name kind type fields methods)`."],
  ] },

  { column: 4, title: "Toolbox", rows: [
    ["%(git status).job().output()", "`process.x`: a command is a `List`; `lines run start`."],
    ["Path p = \".\";  p.join(\"*.x\").glob()", "`path.x`: `read_text write_text make_dirs`."],
    ["args", "A script's arguments; `args.x` parses options."],
    ["Socket.connect(host, port, ms)", "`net.x`: blocking TCP; `Listener.bind`, `accept`."],
    ["Router.new().get(path, %!(req, res) => ...)", "`http.x`: routes, `res.json`, static files."],
    ["HttpServer.new(routes, {port: 0}).start()", "Port 0 picks one; `server.port()`."],
    ["Json.parse(s)  v.json()", "`json.x`; also `time random encoding url regex`."],
  ] },
  { column: 4, title: "Tests", rows: [
    ["$test() static void t(void) { ... }", "`test.x` registers it; end with `$test.main();`."],
    ["$expect(c)  $expect_eq(a, b)", "Keep going after a failure; show both values."],
    ["$expect_raises(<cause>, { ... })", "Passes only when that cause is raised."],
    ["x2c test --filter name", "Every test file in the project."],
  ] },
  { column: 4, title: "C", rows: [
    ["#define FIELDS(X) X(a) X(b)", "X-macros, `#ifdef`, token pasting all expand first."],
    ["p.field  p->field", "`.` reaches through one pointer; `->` still works."],
    ["String.new(cstr)", "Into a `String`; out again as a `char *`."],
    ["x2c build -I dir -O2 main.x", "Include directories and optimization pass to `cc`."],
    ["x2c bind --package p --header p.h", "A package skeleton from a header."],
  ] },
  { column: 4, title: "Commands", rows: [
    ["run  build  translate  script", "`--dump-ast` and `--dump-transforms` look inside."],
    ["new  test  repl  lsp", "A project, its tests, a REPL, an editor server."],
    ["install  package  env", "Packages from the index; what is installed."],
  ] },
];
