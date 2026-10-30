/*  repl-native.x -- native submissions with stable session bindings

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "repl-types.x"
#include "ast-rewrite.x"
#include "callables/callables.x"
#include "expressions/expressions.x"
#include "meta-group/meta-group.x"
#include "utils.x"
#include "scope/scope.x"
#include <stdint.h>

List repl_render(Compiler c, Type type, List expression, List output,
                 int depth, int limit);

static typedef struct NativeSubmission {
  ReplSession session;
  List syntax, environment, original, entry;
  Type type;
  Map captures, objects;
  Array values, identities, body;
  int persistent, prints;
} NativeSubmission;

/** Allocates native storage at the alignment the host compiler supplied. */
void *repl_native_storage(size_t size, size_t alignment) {
  uintptr_t base = (uintptr_t) xmalloc(size + alignment - 1);
  return (void *) ((base + alignment - 1) & ~(uintptr_t) (alignment - 1));
}

static List _native_capture(
  NativeSubmission &n, Var identity, void *address, Type type) {
  Compiler c = n.session.compiler;
  Var index;
  if (!n.captures.try_get(identity, index)) {
    index = (int) n.values.len();
    n.captures[identity] = index;
    n.values.push(address);
    n.identities.push(identity);
  }
  List slot = %(expr (* void)
    (index $(n.environment) $($!int{ $index })));
  return %(expr $type (cast $type $slot));
}

static List _native_name(NativeSubmission &n, Type type, List binding) {
  if (binding == n.original)
    return %(expr $type (ident $(n.entry)));
  Var object;
  if (n.objects.try_get(binding, object)) {
    List pointer = object;
    Type address = type.reference();
    return %(expr $type
      (op * (expr $address (cast $address $pointer))));
  }
  String name = Ast.binding_spelling(binding);
  Type global_type = NULL;
  List global = name ? n.session.compiler.sym.resolve_global($(name), global_type)
                     : NULL;
  if (!global || global != binding) return NULL;
  if (n.session.program) {
    Map description = n.session.program.descriptions[name];
    if (description && description["unavailable"] is not void)
      raise %(repl (reason $("the loaded native library does not provide: " + name)));
  }
  if (!(name in n.session.addresses)) return NULL;
  Var stored = n.session.addresses[name];
  Type address = global_type.is_function()
    ? global_type.reference() : type.reference();
  List captured = _native_capture(n, binding, stored.pointer(), address);
  return global_type.is_function() ? captured : %(expr $type (op * $captured));
}

static Var _native_rewrite(NativeSubmission &n, Var node) {
  if (node is not <list>) return node;
  match (node) {
    case %(expr ?type (ident ?binding)): {
      List result = _native_name(n, type, binding);
      if (result) return result;
    }
    case %(expr ?type (op & (!set ?value (expr ?(Type source) ?))))
      if (source.is_function()): return _native_rewrite(n, value);
  }
  List child;
  $ast.rewrite_children(node, child, _native_rewrite(n, child));
}

static List _native_function(Compiler c, Type type, List binding, List body) {
  List declaration = type.declaration_ast(binding);
  return %(function (static @(declaration.cadr()))
    $(declaration.caddr().cadr()) $body);
}

static List _native_expr(Compiler c, Type type, List binding) =>
  %(expr $type (ident $binding));

static List _native_result_set(
  Compiler c, List result, String name, List value) =>
  c.rebuild_statement($!{ $result[$name] = $value; });

static void _native_object(
  NativeSubmission &n, Type spec, List row, List result) {
  Compiler c = n.session.compiler;
  List bound = row, initial = NULL;
  match (row) case %(op = ?target ?value): {
    bound = target;
    initial = value;
  }
  List binding = NULL, mods = NULL;
  match (bound) case %(bind ?found ?modifiers): {
    binding = found;
    mods = modifiers;
  }
  if (!Ast.try_binding(binding, NULL, NULL))
    raise %(repl (reason "a persistent declaration needs a named object"));
  Type type = %(declare $spec (bindings $bound)).type_from_ast().declared();
  if (type.is_function()) return;
  String name = Ast.binding_spelling(binding);
  List pointer_binding = c.sym.introduce(
    %"__repl_object_$(binding.cadr())");
  List pointer = _native_expr(c, %(* void), pointer_binding);
  c.add_early(c.bind_syntax(
    $!Unit{ static void *$pointer_binding; }, <unit>, NULL));
  n.objects[binding] = pointer;
  List temporary = c.sym.introduce(%"__repl_initial_$(binding.cadr())");
  List declaration = %(declare $spec (bindings
    (op = (bind $temporary $mods)
      $(initial ? _native_rewrite(n, initial) : %(composite (commas))))));
  c.sym.bind_identity(NULL, temporary, declaration);
  n.body.push(declaration);
  List value = _native_expr(c, type, temporary);
  List allocator = c.sym.reference_global(%("repl_native_storage"));
  List allocate = c.rebuild_statement($!{
    $pointer = $allocator(sizeof($value), _Alignof(__typeof__($value)));
  });
  n.body.push(allocate);
  n.body.push(c.rebuild_statement($!{
    memcpy($pointer, (const void *) &$value, sizeof($value));
  }));
  n.body.push(_native_result_set(c, result, name, pointer));
  if (type.is_array() && !type.car().list().cdr()) {
    List extent = c.resolve_expression(
      $!size_t{ sizeof($value) / sizeof($value[0]) }, NULL);
    n.body.push(_native_result_set(c, result, "extent:" + name, extent));
  }
}

static void _native_defer(NativeSubmission &n, List body) {
  Compiler c = n.session.compiler;
  List name = c.sym.introduce(c.fresh_name("repl_cleanup"));
  List function = _native_function(
    c, %((func ((void))) void), name,
    %(block $(_native_rewrite(n, body))));
  c.add_early(function);
  List entry = _native_expr(c, %((func ((void))) void), name);
  List callable = c.convert_expression(entry, %("Func"));
  List cleanups = _native_capture(
    n, %(<cleanups>), (void *) n.session.cleanups, %("Array"));
  n.body.push(c.rebuild_statement($!{ $cleanups.push($callable); }));
}

static void _native_statements(
  NativeSubmission &n, List statements, List result) {
  Compiler c = n.session.compiler;
  foreach (List anchored, statements) {
    List statement = Ast.without_origin(anchored);
    if (statement ~= %(seq *items)) {
      _native_statements(n, items, result);
      continue;
    }
    if (n.persistent) {
      match (statement) {
        case %(declare ?spec (bindings *rows)): {
          foreach (List row, rows) _native_object(n, spec, row, result);
          continue;
        }
        case $deferred(?finalizer): {
          _native_defer(n, finalizer);
          continue;
        }
      }
    }
    n.body.push(_native_rewrite(n, anchored));
  }
}

static void _native_render(
  NativeSubmission &n, List expression, List result) {
  Compiler c = n.session.compiler;
  expression = _native_rewrite(n, expression);
  Type type = expression.cadr();
  if (type.is_bitfield()) {
    type = type.base_type();
    expression = %(expr $type (cast $type $expression));
  }
  List value = expression;
  if (type.is_array()) {
    List name = c.sym.introduce(c.fresh_name("repl_array_result"));
    Type pointer = type.reference();
    List declaration = pointer.declaration_ast(name);
    declaration = %(declare $(declaration.cadr()) (bindings
      (op = $(declaration.caddr().cadr()) (expr $pointer (op & $expression)))));
    c.sym.bind_identity(NULL, name, declaration);
    n.body.push(declaration);
    value = %(expr $type (op * $( _native_expr(c, pointer, name) )));
  }
  else {
    List name = c.sym.introduce(c.fresh_name("repl_result"));
    List declaration = %(declare ("__typeof__" (parens $expression))
      (bindings (op = (bind $name ()) $expression)));
    c.sym.bind_identity(NULL, name, type);
    n.body.push(declaration);
    value = _native_expr(c, type, name);
  }
  List output_binding = c.sym.introduce(c.fresh_name("repl_output"));
  c.sym.bind_identity(NULL, output_binding, %("Buffer"));
  List output = _native_expr(c, %("Buffer"), output_binding);
  n.body.push(c.rebuild_statement($!{ Buffer $output_binding = Buffer.new(128); }));
  n.body.push(repl_render(c, type, value, output,
    n.session.inspect_depth, n.session.inspect_limit));
  List formatted = c.resolve_expression($!String{ $output.str() }, NULL);
  n.body.push(_native_result_set(c, result, "formatted", formatted));
  n.body.push(c.rebuild_statement($!{ $output.free(); }));
}

static List _native_prepare(Compiler c, NativeSubmission &n) {
  List env = c.sym.introduce("__repl_environment");
  n.environment = _native_expr(c, %(* * void), env);
  c.add_early(c.bind_syntax($!Unit{ static void **$env; }, <unit>, NULL));
  List allocator = c.sym.introduce("repl_native_storage");
  c.add_early(c.bind_syntax(
    $!Unit{ void *$allocator(size_t size, size_t alignment); },
    <unit>, NULL));
  List argument = c.sym.introduce("__repl_captures");
  List parameter = _native_expr(c, %(* void), argument);
  List returned = c.sym.introduce("__repl_response");
  List result = _native_expr(c, %("Map"), returned);
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  c.sym.bind_identity(NULL, argument, %(* void));
  c.sym.bind_identity(NULL, returned, %("Map"));
  n.body.push(c.rebuild_statement($!{ Map $returned = {}; }));
  if (n.syntax ~= %(function ?spec (bind ?original ?mods) ?body)) {
    n.original = original;
    n.type = %(declare $spec (bindings (bind $original $mods))).type_from_ast();
    n.entry = c.sym.introduce(
      %"__repl_native_$(original.cadr())_$(Ast.binding_spelling(original))");
    List storage = n.type.is_static() ? spec : cons(<static>, spec);
    c.add_early(%(function $storage (bind $(n.entry) $mods)
      $(_native_rewrite(n, body))));
    List target = _native_expr(c, n.type, n.entry);
    n.body.push(_native_result_set(c, result,
      Ast.binding_spelling(original), c.resolve_expression(
        $!(void *){ (void *) &$target }, NULL)));
  }
  else {
    List statements = n.syntax;
    if (n.syntax ~= %(block *items)) statements = items;
    if (n.prints && statements) {
      Array parts = auto statements;
      List last = Ast.without_origin(parts[parts.len() - 1]);
      if (last ~= %(stmnt ?expression)) {
        parts.pop();
        _native_statements(n, parts, result);
        _native_render(n, expression, result);
      }
    }
    else _native_statements(n, statements, result);
  }
  List initialize = c.rebuild_statement($!{
    if (!$(n.environment))
      $(n.environment) = (void **) xmemdup(
        $parameter, $(n.values.len() * sizeof(void *)));
  });
  List setup = n.body;
  List body = %(block $initialize @setup (return ("Map") $result));
  return c.bind_syntax(
    %(function ("Map")
      (bind $(c.sym.introduce("__repl_factory"))
        ((fnmod (params (param (* void) (bind $argument ())))))) $body),
    <unit>, NULL);
}

/** Compiles one entry with the session's native configuration and runs it. */
Map repl_native_execute(ReplSession session, List syntax, int persistent,
                        int prints) {
  NativeSubmission n = {
    .session = session, .syntax = syntax, .persistent = persistent,
    .prints = prints, .captures = {}, .objects = {},
    .values = [], .identities = [], .body = []
  };
  defer {
    n.captures.cleanup(); n.objects.cleanup();
    n.values.free(); n.identities.free(); n.body.free();
  }
  String failure = NULL;
  List code = session.compiler.emit_session_function(
    session.declarations,
    %!(Compiler c) using &n => _native_prepare(c, n), failure);
  if (!code) raise %(repl (reason $failure));
  (String hname, String header, String cname, String source) = code;
  CliRequest request = session.frontend ? session.frontend.request : NULL;
  String configuration = request
    ? $(request.cc_args, request.ld_args, request.include_dirs).repr() : "";
  String runtime_headers = NULL;
  Toolchain toolchain = session.frontend
    ? session.frontend.toolchain
    : Toolchain.for_meta(Compiler.meta_cc(runtime_headers));
  // Each load builds in a new directory; the entry depends only on content.
  String content = header + source;
  ReplProgram program = session.program;
  if (program)
    content = (content + Path.read_text(program.header))
      .replace(program.directory, "");
  String identity = String.sha256(
    content + n.identities.repr() + configuration + Compiler.module_stamp() +
    Compiler.meta_cc_identity(toolchain.cc) + toolchain.include_dir);
  String directory = %"$(Compiler.cache_root())/repl/$identity";
  String module = %"$directory/group.module";
  if (!Path.is_file(module)) {
    Path.make_dirs(directory);
    Path.write_text(%"$directory/$hname", header);
    Path.write_text(%"$directory/$cname", source);
    List inputs = $("-fPIC", "-O0", "-iquote", directory,
      "-iquote", toolchain.include_dir, @(toolchain.cc_args),
      %"$directory/$cname");
    String output = %"$module.$((long) getpid())";
    ToolAction action = toolchain.module_action(output, inputs, x2c_get_executable());
    failure = Compiler.meta_cc_run(action.arguments, directory);
    if (failure) raise %(repl (reason $failure));
    Path.move_to(output, module);
  }
  String loaded = Compiler.load_native_module(module);
  Map targets = Compiler.native_module_targets(loaded);
  Func factory = targets["__repl_factory"];
  void **captures = xcalloc(n.values.len() + 1, sizeof(void *));
  defer xfree(captures);
  for (int i = 0; i < n.values.len(); i++) captures[i] = n.values[i].pointer();
  FuncArg argument = FuncArg.value(Var.new(<p48>, captures));
  try {
    Map published = factory.apply(1, &argument);
    published["artifact"] = directory;
    return published;
  }
  catch %(?kind *details): raise %(replrun (cause $(cons(kind, details))));
  return NULL;
}
