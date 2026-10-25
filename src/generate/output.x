/*  output.x -- assemble and publish generated files */

/* Where generated code must precede its first use in a unit's source:
   `function` before the first function or captured initializer, and
   `error` before the first raise or declaration that needs the lowered
   catch ABI. Each position moves out to the directive opening the outermost
   conditional group around its item, so the code is declared whichever
   arms the C compiler selects. A missing use gives -1. */
static typedef struct Anchors { int function, error; } Anchors;
// diagnostics

static macro Stmt $fail.generate_file_write(
  Expr $c, Expr $site, Expr $failure) {
  {
    String reason = String.new(strerror((int) $failure.assoc(<"errno">)));
    $c.report_error(
      <emit>, "failed to write generated file",
      $site, %("file: $($failure.assoc(<path>))" "reason: $reason"));
  }
}

// generating a unit

/** Writes the generated C header and source for one lowered translation unit.
    `ast` must be the normalized result of `transform_ast` for this compiler;
    its filename, symbols, binding facts, cache keys, and initialization state
    must still describe that same unit. `dir` must already exist. Generation
    partitions the AST, materializes caches and once-only initialization, and
    writes or replaces `<dir>/<source-stem>.h`, `.c`, and the `.xi` interface
    of a collected unit through one `Path.publish_files`, so a failed write
    replaces none of them. It appends generated bindings and initialization
    work to the compiler and is not idempotent. Failures are reported as
    `emit` diagnostics.
*/
void Compiler.generate_code(Compiler c, List ast, String dir) {
  ast = _without_trivia(ast);
  String basename = %"$(dir.rstrip("/"))/$(Path.stem(c.filename))";
  List outputs = _generated_code(c, ast, basename);
  String interface = c.source_facts ? NULL : c.interface_text();
  if (interface) outputs = outputs.append(%("$basename.xi" $interface));
  _publish_files(c, outputs);
}

/** Returns the generated header and source of the lowered `ast` as `(hfile
    htext cfile ctext)`, named from `basename`, without writing them. It
    affects the compiler as `Compiler.generate_code` does. */
List Compiler.generate_code_text(Compiler c, List ast, String basename) =>
  _generated_code(c, _without_trivia(ast), basename);

static List _without_trivia(List ast) =>
  ast.filter(%!(node) => !node.list().match(%((!or space comment empty) *)));

/* The header and source of `ast` as `(hfile htext cfile ctext)`, named from
   `basename`. */
static List _generated_code(Compiler c, List ast, String basename) {
  Map inline_bodies = auto {};
  List (header, source) = _header_and_source(c, ast, inline_bodies);
  String hash = Path.identifier_hash(c.filename);
  Map bindings;
  (header, source, bindings) = c.setup_cache_init(
    header, source, %"_x2c_gensym_hcache_$(hash)_",
    %"_x2c_gensym_hcache_guard_$hash",
    %"_x2c_gensym_hcache_init_$hash");
  defer bindings.cleanup();
  List hcode = _emit_header(c, header);
  List ccode = _emit_source(c, source, bindings, inline_bodies);
  String hfile = %"$basename.h", cfile = %"$basename.c";
  return %(
    $hfile $(c.code_pretty_string(hcode, hfile))
    $cfile $(c.code_pretty_string(ccode, cfile))
  );
}

static List _emit_header(Compiler c, List header) {
  header = _forward_declarations(c, header, 0);
  return c.emit(_include_guard(c, _vertical_spacing(header)), NULL);
}

/* Each source use follows the declarations it needs. */
static List _emit_source(
  Compiler c, List source, Map bindings, Map inline_bodies) {
  source = _forward_declarations(
    c, _move_bodies(_file_init(c, source), inline_bodies), 1);
  return c.emit(_source_unit(c, source), bindings);
}

/* A failed write reports its file and the host error. */
static void _publish_files(Compiler c, List outputs) {
  List failure = NULL;
  try Path.publish_files(outputs);
  catch %((!or not-found io-fail) *detail): failure = Error.snapshot(detail);
  if (!failure) return;
  $fail.generate_file_write(c, c.token, failure);
}

/** Places generated `declarations` after source types and includes, before
    the first function or captured initializer that can use them. An outer
    conditional containing that first use follows the declarations. A unit
    without such a use gets them at its end, after the declarations they
    may assign.
*/
List Compiler.place_source_prelude(
  Compiler c, List source, List declarations) {
  (void) c;
  Array out = [];
  int prelude = _anchors(source, 0).function, position = 0;
  foreach (List node in source) {
    if (position++ == prelude)
      foreach (List declaration in declarations) out.push(declaration);
    out.push(node);
  }
  if (prelude < 0)
    foreach (List declaration in declarations) out.push(declaration);
  return out.list_free();
}

/* The anchors of `source`; `error` is sought only with `errors`. */
static Anchors _anchors(List source, int errors) {
  Anchors at = {-1, -1};
  int position = 0, depth = 0, opening = 0;
  foreach (List item in source) {
    int here = depth ? opening : position;
    if (at.function < 0 && _is_function(item)) at.function = here;
    if (errors && at.error < 0 && _needs_errors(item)) at.error = here;
    if (at.function >= 0 && (!errors || at.error >= 0)) break;
    match (item) case %(preproc ?(String content)): {
      Symbol kind = Compiler.preproc_conditional_kind(content);
      if (kind == <open> && !depth) opening = position;
      if (kind == <open>) depth++;
      else if (kind == <close> && depth) depth--;
    }
    position++;
  }
  return at;
}

static int _is_function(List item) {
  List function = item.car() == <sourceinit> ? item.cadr() : item;
  match (function)
    case %(function (*) (bind (binding ? ?) ?) (block *)): return 1;
  return 0;
}

static int _needs_errors(List item) {
  Map types = auto {};
  _spelled_types(item, types);
  return Ast.contains_head(item, <raise>) ||
    "ErrorCatchSite" in types || "ErrorHandler" in types;
}

/* file text

   Both files open with the generated banner. The header guards its public
   declarations; the source suppresses cyclic includes of that header and
   consumes its own ordered declarations. */

static List _vertical_spacing(List code) {
  Array out = [];
  foreach (List node in code) _push_line(out, node);
  return out.list_free();
}

static void _push_line(Array out, Var node) {
  out.push(node);
  out.push(%(space "\n"));
}

/* A unit that uses the runtime includes it inside the header's guard. */
static List _include_guard(Compiler c, List content) {
  if (c.runtime_inc && !_has_runtime_include(content))
    content = cons(%(preproc "#include \"x2c.x\""), content);
  return %(@(_banner()) @(_header_guard(content, c.header_guard())));
}

static int _has_runtime_include(List content) {
  foreach (List node in content) match (node) case %(preproc ?(String text)): {
    int angle = 0;
    if (Compiler.preproc_include_target(text, angle) == "x2c.x") return 1;
  }
  return 0;
}

static List _banner(void) => %(
    (comment "/* auto-generated by x2c.  Do not edit! */")
    (space "\n")
    (space "\n")
  );

static List _header_guard(List content, String guard) => %(
    (preproc "#pragma once")
    (space "\n\n")
    (preproc "#ifndef $guard")
    (space "\n")
    (preproc "#define $guard")
    (space "\n\n")
    @content
    (space "\n")
    (preproc "#endif /* $guard */")
    (space "\n")
  );

/** Returns the guard macro of the header generated for this unit, named
    from its path below the home when it has one there, else as spelled, so
    a meta group that copies the unit names the same guard. */
String Compiler.header_guard(Compiler c) {
  String home = Compiler.home_dir(), name = c.filename;
  String path = home ? Path.absolute(name) : NULL;
  if (path && path.startswith(%"$home/")) name = path[home.len() + 1:];
  return %"__GUARD_0x$(Path.identifier_hash(name))__";
}

/* The source defines its own header's guard, so a cyclic include of that
   header adds nothing; its own declarations follow in order. The runtime
   headers that lowering needs precede their first uses. */
static List _source_unit(Compiler c, List content) {
  List runtime = c.runtime_inc ? _include_directive("x2c.x") : NULL;
  Anchors at = _anchors(content, 1);
  List error = at.error >= 0 ? _include_directive("error.h") : NULL;
  List exception =
    c.needs_exception ? _include_directive("exception.h") : NULL;
  Array lines = [];
  int position = 0;
  foreach (List node in content) {
    if (position == at.error)
      foreach (List include in error) _push_line(lines, include);
    if (position++ == at.function)
      foreach (List include in exception) _push_line(lines, include);
    _push_line(lines, _runtime_entry(c, node));
  }
  return %(@(_banner()) (preproc "#define $(c.header_guard())") @runtime
           @(lines.list_free()));
}

/* `main` initializes the runtime before anything else, including its file
   initialization guard. Its prototype comes from the runtime header, so
   the call is added after forward declarations. */
static List _runtime_entry(Compiler c, List node) {
  match (node)
    case %(function ? (bind (binding ? "main") ?) (block *body)): {
      List initializer = c.sym.reference(%("x2c_initialize"), NULL);
      List setup = %((stmnt (expr (void) (call
        (expr ((func ((void))) void) (ident $initializer))
        (args (expr (void) ()))))));
      return _replace_body(c, node, setup.append(body));
    }
  return node;
}

static List _include_directive(String fname) =>
  %((preproc "#include \"$fname\"") (space "\n") (space "\n"));
