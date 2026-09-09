/*  emit.x -- emit C tokens from x2c ASTs

    Translates normalized ASTs into token `List`s for downstream flattening and
    formatting. One stack-local Emitter holds cleanup guards and preserved
    automatic names, so emission is reentrant and a failed translation cannot
    contaminate later units. Cleanup lowering preserves handler order and the
    active exit kind across returns and loop exits.

*/

#pragma once

#include "compiler.x"
#pragma private
#include <stdlib.h>
#include <stdio.h>
#include "string.x"
#include "var.x"
#include "ast.x"

typedef enum ExitKind {
  _cleanup_exit_normal,
  _cleanup_exit_return,
  _cleanup_exit_break,
  _cleanup_exit_continue,
  _cleanup_exit_goto
} ExitKind;

typedef struct Cleanup {
  List final_code, leave_stmt, String guard;
} Cleanup;

// Per-emission state.
typedef struct Emitter {
  delegate Compiler compiler;
  Block cleanups;
  // Cleanup-stack depths recorded when the innermost enclosing loop or
  // switch body was entered. "break" and "continue" only transfer control
  // inside that construct, so they must not run or pop cleanup records
  // registered outside it. "return" leaves the function and runs cleanup
  // records from depth zero.
  int break_stop;
  int continue_stop, List cleanup_path, Map label_paths, List volatile_names;
  Type return_type, int origin, String fn_name;
} *Emitter;

static List Emitter._commas(Emitter emitter, List lst) {
  (void) emitter;
  if (!lst.cdr()) return lst;
  Array result = %[];
  int first = 1;
  foreach (Var item, lst) {
    if (!first) result.push(%", ");
    result.push(item);
    first = 0;
  }
  return result.list_free();
}

// Wrap declarators in parentheses when pointer precedence requires it.
static List _parens(List decl) => %("(" @decl ")");
static List Emitter._function_declarator(
  Emitter emitter, List decl, List func, List mods) {
  if (decl.type().is_pointer()) decl = _parens(decl);
  List params = func.cadr();
  params = emitter._emit(params, NULL);
  return emitter._declarator(%( @decl "(" @params ")"), mods);
}

static List Emitter._bitfield_declarator(
  Emitter emitter, List decl, List bits_list, List mods) {
  List size = emitter._emit(bits_list.cadr(), NULL);
  decl = %( @decl ":" @size );
  return emitter._declarator(decl, mods);
}

static List Emitter._array_declarator(
  Emitter emitter, List decl, List array_list, List mods) {
  if (decl.type().is_pointer()) decl = _parens(decl);
  List size = array_list ? emitter._emit(array_list.cadr(), NULL) : NULL;
  decl = size ? %( @decl "[" @size "]") : %( @decl "[]");
  return emitter._declarator(decl, mods);
}

/* Lower each x2c `&` modifier to C `*` only as its declarator layer is
   folded. Do not recursively rewrite `mods`: nested `fnmod` parameter trees
   may be flat and must not consume one C stack frame per parameter. */
static List Emitter._pointer_declarator(
  Emitter emitter, List decl, List mods) {
  Var first = car(mods);
  if (first == <&>)
    return emitter._declarator(cons(<*>, decl), cdr(mods));
  if (first == <*> || Symbol.is_type_qualifier(first))
    return emitter._declarator(cons(first, decl), cdr(mods));
  return %( @mods @decl );
}

static List Emitter._declarator(Emitter e, List decl, List mods) {
  if (!mods) return decl;
  Var first = car(mods);
  if (first is <list>) {
    Type mod = first;
    if (car(mod) == <fnmod>)
      return e._function_declarator(decl, mod, cdr(mods));
    if (mod.is_array()) return e._array_declarator(decl, mod, cdr(mods));
    return e._bitfield_declarator(decl, mod, cdr(mods));
  }
  Symbol sym = first;
  switch (sym) {
    case <dim>: return e._array_declarator(decl, NULL, cdr(mods));
    case <*>: case <&>:
      return e._pointer_declarator(decl, mods);
    case <bitfield>:   return e._emit(cdr(mods), NULL);
    case <typedef>:
      return cons(<typedef>, e._declarator(decl, cdr(mods)));
  }
  if (sym.is_type_qualifier()) return e._pointer_declarator(decl, mods);
  return %( @mods @decl );
}

static String _addressed_identifier(Var value) {
  if (value is not <list>) return NULL;
  List ast = value;
  match (ast) {
    case %(expr ? ?inner): return _addressed_identifier(inner);
    case %(parens ?inner): return _addressed_identifier(inner);
    case %(op & ?inner):   return _direct_identifier(inner);
  }
  return NULL;
}

static String _direct_identifier(Var value) {
  while (value is <list>) {
    List ast = value;
    match (ast) {
      case %(ident ?binding):
        return binding_identity_spelling(binding);
      case %(!or (expr ? ?inner) (parens ?inner)): {
        value = inner;
        continue;
      }
      case %(index (!set ?base (expr ?base_type ?)) ?): {
        Type type = base_type;
        if (type.is_array()) {
          value = base;
          continue;
        }
      }
      case %(op . ?base *): {
        value = base;
        continue;
      }
      case %(op (!quote ->) ?base *): return _addressed_identifier(base);
      case %(op (!quote *) ?base): return _addressed_identifier(base);
    }
    return NULL;
  }
  return NULL;
}

// C requires automatic state changed after sigsetjmp to be volatile after
// siglongjmp.
static Ast Emitter._preserve_bindings(Emitter e, Ast ast) {
  if (!ast) return ast;
  Var head = ast.car();
  if (head == <bind>) {
    List (name, mods) = ast.cdr();
    String spelling = binding_identity_spelling(name);
    if (e.volatile_names.contains(spelling) &&
        !mods.contains(<volatile>))
      mods = cons(<volatile>, mods);
    return %(bind $name $mods);
  }
  if (head is <list>) head = e._preserve_bindings(head);
  return cons(head, e._preserve_bindings(ast.cdr()));
}

static int _bindings_need_preservation(Emitter emitter, List bindings) {
  foreach (Ast binding, bindings.cdr()) match (binding)
    case %(!or (bind ?name ?) (op = (bind ?name ?) ?)): {
      String spelling = binding_identity_spelling(name);
      if (emitter.volatile_names.contains(spelling)) return 1;
    }
  return 0;
}

// Static, extern, and typedef declarations do not have automatic storage.
/* A `threaded` object has static storage duration, one copy per thread, so
   like a static it is not automatic and needs no volatile preservation
   across a sigsetjmp boundary. */
static int _is_automatic_declaration(List ast) {
  Type type = ast.cadr();
  return !type.is_static() && !type.is_extern() && !type.is_typedef() &&
         !type.is_threaded();
}

static List Emitter._bind(Emitter emitter, Ast ast, List context) {
  List (ident, mods) = ast.cdr();
  ident = emitter._emit(ident, NULL);
  if (!mods) return ident;
  return emitter._declarator(ident, mods);
}

static List Emitter._param(Emitter e, List ast, List context) {
  List (type, mods) = ast.cdr();
  context = %( $type );
  mods = %( $mods );
  if (e.volatile_names) mods = e._preserve_bindings(mods);
  return context.append(e._emit(mods, NULL));
}

static List Emitter._args(Emitter emitter, List ast, List context) {
  (void) context;
  Array result = %[];
  int first = 1;
  foreach (List argument, cdr(ast)) {
    List emitted = emitter._emit(argument, NULL);
    if (argument.match(%(expr ? (commas *)))) emitted = _parens(emitted);
    if (!first) result.push(%", ");
    result.push(emitted);
    first = 0;
  }
  return result.list_free();
}

static List Emitter._declare(Emitter emitter, List ast, List context) {
  List (type, bindings) = ast.cdr();
  type = emitter._emit(%( $type ), NULL);
  bindings = %( $bindings );
  return type.append(emitter._emit(bindings, type));
}

static String _cleanup_label_spelling(Var value) {
  String direct = _direct_identifier(value);
  if (direct) return direct;
  if (value is not <list>) return NULL;
  List label = value;
  return label && !label.cdr() && label.car() is <string>
       ? label.car().string() : NULL;
}

// Record label ancestry and automatic assignments inside try regions in one
// function walk. Paths are innermost-first canonical Lists; a legal outward
// target is therefore a suffix of the source path.
static void Emitter._collect_function_state(
  Emitter e, List ast, List path, int in_try) {
  // Nested lists continue in this frame, with pending sibling suffixes and
  // their `in_try` states parked on `resume`, so nesting depth never costs
  // C stack. Statement-scoped cases below still recurse with a new path.
  Array resume = %[];
  Array resume_try = %[];
  defer resume.free();
  defer resume_try.free();
  for (;;) {
    if (!ast) {
      if (!resume.len()) return;
      ast = resume.take_last();
      in_try = (int) resume_try.take_last().integer();
      continue;
    }
    Var head = ast.car();
    if (head is <list>) {
      if (ast.cdr()) {
        resume.push(ast.cdr());
        resume_try.push(in_try);
      }
      ast = head;
      continue;
    }
    if (head is not <symbol>) {
      ast = ast.cdr();
      continue;
    }
    if (head == <try>) in_try = 1;
    String name = NULL;
    if (in_try) {
      match (ast) {
        case %(op ?operator ?target *):
          if (operator is <symbol> &&
              ast_changes_left_operand(operator))
            name = _direct_identifier(target);
        case %((!or vcompound vpostfix) ?target *):
          name = _direct_identifier(target);
        case %(postfix ? ?target): name = _direct_identifier(target);
      }
      if (name && !e.volatile_names.contains(name))
        e.volatile_names = cons(name, e.volatile_names);
    }
    switch (head.symbol()) {
      case <at>:
        ast = ast.caddr();
        continue;
      case <label>: {
        String name = _cleanup_label_spelling(ast.cadr());
        if (name) e.label_paths.setindex(name, path);
        ast = NULL;
        continue;
      }
      case <defer>: {
        List body = ast.cadr(), written = ast.last();
        if (in_try) foreach (List binding, written) {
          String captured = binding_identity_spelling(binding);
          if (!e.volatile_names.contains(captured))
            e.volatile_names = cons(captured, e.volatile_names);
        }
        e._collect_function_state(body, cons(body, path), in_try);
        ast = NULL;
        continue;
      }
      case <try>: {
        List (body, clause, finalizer) = ast.cdr();
        e._collect_function_state(body, cons(body, path), in_try);
        if (clause) {
          foreach (List record, clause.cadr()) {
            e._collect_function_state(record.car(), path, in_try);
            e._collect_function_state(record.cadr(), path, in_try);
            List arm = record.caddr();
            e._collect_function_state(arm, cons(arm, path), in_try);
          }
        }
        if (finalizer)
          e._collect_function_state(finalizer, path, in_try);
        ast = NULL;
        continue;
      }
      case <function>: ast = NULL; continue;
    }
    ast = ast.cdr();
  }
}

static List Emitter._function(Emitter e, List ast, List context) {
  List (type, bindings, body) = ast.cdr();
  List declaration = %(declare $type (bindings $bindings));
  Type old_return_type = e.return_type, String old_fn = e.fn_name;
  e.return_type = cdr(declaration.type_from_ast()).type().declared();
  List function_binding = bindings.cadr();
  e.fn_name = binding_identity_spelling(function_binding);
  Var defer_owner;
  if (e.semantic_binding_facts().try_get(
    %(defer-ownr $function_binding), &defer_owner))
    e.fn_name = defer_owner.str();
  type = e._emit(%( $type ), NULL);
  bindings = %( $bindings );
  body = %( $body );
  List previous = e.volatile_names, Map old_labels = e.label_paths;
  List old_path = e.cleanup_path;
  e.label_paths = %{};
  e.cleanup_path = NULL;
  e.volatile_names = NULL;
  e._collect_function_state(body, NULL, 0);
  // No loop or switch spans a function boundary, so a nested body starts
  // with the barriers cleared rather than inheriting an enclosing loop's.
  int prev_break, prev_continue;
  e._cleanup_barrier_enter(1, &prev_break, &prev_continue);
  List decl = e._emit(bindings, type), body_code = e._emit(body, NULL);
  e._cleanup_barrier_leave(prev_break, prev_continue);
  e.label_paths = old_labels;
  e.cleanup_path = old_path;
  e.volatile_names = previous;
  e.return_type = old_return_type;
  e.fn_name = old_fn;
  return %(@type @decl @body_code);
}

// Emit a checked native-function alias without a wrapper object.
static List Emitter._foreign_alias(
  Emitter e, List ast, List context) {
  (void) context;
  List (declaration, native_binding) = ast.cdr();
  List bindings = declaration.caddr(), target = bindings.cadr().cadr();
  Type function_type = declaration.type_from_ast().declared();
  Type pointer_type = function_type.reference();
  List pointer = e._semantic_type(pointer_type);
  List native = e._emit(native_binding, NULL);
  String target_name = e.emitted_binding_name(target);
  String native_name = e.emitted_binding_name(native_binding);
  String message = %"native alias $target_name does not match $native_name";
  String define = %"#define $target_name $native_name";
  return %(
    "#ifndef X2CCPP"
    "_Static_assert("
    "_Generic(&" @native ", " @pointer ": 1, default: 0), "
    "\"$message\");"
    "#endif"
    $define
  );
}

/* The tag slot of an anonymous aggregate holds the compiler-internal
   gensym key that stands in for the tag the source never wrote. It names
   nothing outside this unit, and two units that reach the same counter
   state mint the same key, so it is never emitted. The tagless definition
   is what the source wrote, and tagless typedefs are compatible across
   translation units (C11 6.2.7). */
static int _is_gensym_tag(List tag) {
  if (!tag) return 0;
  Var head = tag.car();
  if (head is not <list>) return 0;
  return head.list().car() == <gensym>;
}

static List Emitter._enum(Emitter emitter, List ast, List context) {
  List name = ast.type().tag(), body = car(ast.type().body());
  if (_is_gensym_tag(name) && !ast.type().is_enum_tag()) name = NULL;
  body = emitter._emit(body, NULL);
  body = emitter._commas(body);
  if (name) {
    if (body) return %( ${car(ast)} @name "{" @body "}");
    return %( ${car(ast)} @name );
  }
  return %( ${car(ast)} "{" @body "}");
}

static List Emitter._aggregate(Emitter emitter, List ast, List context) {
  List tag = ast.type().tag();
  if (_is_gensym_tag(tag) && !ast.type().is_aggregate_tag()) tag = NULL;
  if (tag) tag = emitter._emit(tag, NULL);
  if (ast.type().is_aggregate_tag()) return %( ${car(ast)} @tag );
  List body = ast.type().body();
  body = emitter._emit(body, NULL);
  body = body.flatten_all();
  if (tag && body) return %( ${car(ast)} @tag "{" @body "}");
  if (tag) return %( ${car(ast)} @tag );
  return %( ${car(ast)} "{" @body "}");
}

static List _atom_intern(String spelling) {
  String qq = "\"", text = %"$qq${spelling.escape().replace("$$", "$")}$qq";
  Atom atom = Atom.intern(spelling);
  if (atom is <symbol>) return %( "Symbol_var(Symbol_new($text))" );
  return %( "Atom_intern(String_new($text))" );
}

static List Emitter._literal(Emitter emitter, List ast, List context) {
  (List type, String text, Var value) = ast.cdr();
  if (type === %("Var") && text == %"void") return %("((void) 0, Void)");
  if (type === %("String")) {
    String qq = "\"";
    text = qq + text.escape().replace("$$", "$") + qq;
    return %("String_new" "(" $text ")");
  }
  if (type === %("Symbol")) {
    Symbol symbol = value;
    text = %"${(long) symbol}";
  }
  if (type === %("Atom")) return _atom_intern(text);
  return %( $text );
}

static List Emitter._var_collection(
  Emitter emitter, String type, List elements, List context) {
  if (!elements) return %("${type}_new()");
  List emitted = emitter._commas(emitter._emit(elements, context));
  String count = %"${elements.len()}";
  return %("${type}_update_n(${type}_new(), " $count ", " $emitted ")");
}

static List Emitter._binding(Emitter emitter, List ast, List context) {
  (void) context;
  return %(${emitter.emitted_binding_name(ast)});
}

static List Emitter._semantic_type(Emitter emitter, Type type) {
  List declaration = type.declaration_ast(NULL);
  return emitter._declare(declaration, NULL);
}

static List Emitter._semantic_name(
  Emitter emitter, Type type, String name) {
  List (base, mods) = type.declaration_parts();
  List declarator = emitter._declarator(%($name), mods);
  return %(${emitter._emit(base, NULL)} @declarator);
}

/* Transform has converted every `vseqcall` operand to its parameter type.
   C leaves call-argument evaluation order unspecified, so typed temporaries
   materialize these operands left-to-right before the protocol member call. */
static List Emitter._sequenced_call(
  Emitter e, Var callee, List arguments, List context) {
  List c_fn = e._emit(%($callee), context);
  Array declarations = %[], names = %[];
  foreach (List argument, arguments)
    match (argument)
      case %(expr ?argument_type ?): {
        String name = e.fresh_name("protocol_arg");
        List declaration = e._semantic_name(
          argument_type, name);
        List value = e._emit(%($argument), context);
        declarations.push(%(@declaration "=" @value ";"));
        names.push(name);
      }
  List c_args = e._commas(names.list_free());
  return %("({" @{declarations.list_free()} @c_fn
           "(" @c_args ");" "})");
}

static List Emitter._destructure_value(
  Emitter e, Type type, List result, List source, List temporary,
  List converted, List statements, List context) {
  /* The statement expression evaluates the source once, converts that saved
     value once, performs the producer-ordered assignments, and yields the
     original statically typed result. */
  String result_name = binding_identity_spelling(result);
  String temporary_name = binding_identity_spelling(temporary);
  List result_decl = e._semantic_name(type, result_name);
  List temporary_decl = e._semantic_name(%("List"), temporary_name);
  List c_src = e._emit(%($source), context);
  List c_repr = e._emit(%($converted), context);
  List c_stmts = e._emit(statements, context);
  return %("({" @result_decl "=" @c_src ";"
           @temporary_decl "=" @c_repr ";"
           @c_stmts $result_name ";" "})");
}

// Loop and switch cleanup barriers.
// Record the current cleanup depth as the barrier that "break" must not
// unwind past, saving the outer barriers through the out parameters. Loop
// bodies also bound "continue"; a switch body does not, because "continue"
// inside a switch still targets the enclosing loop. Every caller must pass
// the saved pair back to _cleanup_barrier_leave once the body is emitted.
static void Emitter._cleanup_barrier_enter(
  Emitter e, int is_loop, int *saved_break, int *saved_continue) {
  *saved_break = e.break_stop;
  *saved_continue = e.continue_stop;
  int depth = (int) e.cleanups.length;
  e.break_stop = depth;
  if (is_loop) e.continue_stop = depth;
}

// Restore the barriers that were active before a body was emitted.
static void Emitter._cleanup_barrier_leave(
  Emitter emitter, int saved_break, int saved_continue) {
  emitter.break_stop = saved_break;
  emitter.continue_stop = saved_continue;
}

// Emit pending cleanup down to stop_depth, the cleanup-stack index below
// which unwinding stops. Each record runs its finalizers and then its own
// leave statement, so an inner exception frame leaves before an outer defer
// runs; collecting all finalizers ahead of all leave statements would drop
// the frame's cleanup watermark below its own entries. A guarded record
// samples its guard first, because its finalizers clear it before running.
// The stack is only populated by _cleanup_emit, so payload shape is trusted.
static void _push_fragments(Array output, List fragments) {
  foreach (Var fragment, fragments) output.push(fragment);
}

static List Emitter._cleanup_wrap_exit(
  Emitter e, List statement, ExitKind exit_kind, int stop_depth) {
  int top = (int) e.cleanups.length;
  if (top <= stop_depth) return statement;
  Cleanup *records = e.cleanups.bytes;
  Array cleanup = %[];
  for (int i = top - 1; i >= stop_depth; i--) {
    Cleanup *record = &records[i];
    List final_code = record.final_code, leave_code = record.leave_stmt;
    if (!record.guard) {
      _push_fragments(cleanup, final_code);
      _push_fragments(cleanup, leave_code);
      continue;
    }
    String guard = record.guard, snapshot = e.fresh_name("cleanup_state");
    Array guarded = %[ "$guard = 0;" ];
    _push_fragments(guarded, %("if ($snapshot > 0) {" @final_code "}"));
    guarded.push(%"$guard = -1;");
    _push_fragments(guarded, leave_code);
    _push_fragments(
      cleanup, %(
      "int $snapshot = $guard;"
      "if ($snapshot >= 0) {" @{guarded.list_free()} "}"
    ));
  }
  List cleanup_code = cleanup.list_free();
  String exit_literal = %"$exit_kind";
  String prev_name = e.fresh_name("cleanup_prev");
  return %("{
  int $prev_name = x2c_cleanup_exit_kind;
  x2c_cleanup_exit_kind = $exit_literal;
  "@cleanup_code"
  x2c_cleanup_exit_kind = $prev_name;
  "@statement"
}");
}

static List Emitter._cleanup_wrap_return(Emitter emitter, List statement) =>
  emitter._cleanup_wrap_exit(statement, _cleanup_exit_return, 0);

static List Emitter._cleanup_wrap_break(Emitter emitter, List statement) =>
  emitter._cleanup_wrap_exit(
    statement, _cleanup_exit_break,
    emitter.break_stop);

static List Emitter._cleanup_wrap_continue(Emitter emitter, List statement) =>
  emitter._cleanup_wrap_exit(
    statement, _cleanup_exit_continue,
    emitter.continue_stop);

static List Emitter._cleanup_wrap_goto(
  Emitter emitter, List statement, int stop_depth) =>
    emitter._cleanup_wrap_exit(statement, _cleanup_exit_goto, stop_depth);

static List Emitter._cleanup_emit(
  Emitter e, List final_code, List leave_stmt, String guard, Var ast,
  List context) {
  // Only a try's own finalizer record carries its run-once guard.
  Cleanup record = { final_code, leave_stmt, guard };
  e.cleanups.push(&record);
  e.cleanup_path = cons(ast, e.cleanup_path);
  List out = e._emit(%( $ast ), context);
  e.cleanups.pop();
  e.cleanup_path = e.cleanup_path.cdr();
  return out;
}

// Emit a callable defer region. The runtime record covers nonlocal transfer;
// the emitter cleanup stack covers ordinary fallthrough and structured exits.
static List Emitter._defer(Emitter e, List ast, List context) {
  List (body, env_binding, callback, records, written) = ast.cdr();
  (void) written;
  String cleanup_name = e.fresh_name("defer_record");
  String callback_name = binding_identity_spelling(callback);
  List env_setup = NULL, env_arg = %("NULL");

  if (env_binding) {
    String env_type = binding_identity_spelling(env_binding);
    String env_name = e.fresh_name("defer_env"), Array initializers = %[];
    foreach (List record, records) {
      String source = binding_identity_spelling(record.car());
      String field = binding_identity_spelling(record.caddr());
      initializers.push(%("." $field "=" "(const void *)" "&" $source));
    }
    List values = e._commas(initializers.list_free());
    env_setup = %("$env_type $env_name = {" @values "};");
    env_arg = %("&" $env_name);
  }

  List leave = %("x2c_cleanup_leave(&" $cleanup_name ");");
  List body_code = e._cleanup_emit(leave, NULL, NULL, body, context);
  String previous = e.fresh_name("cleanup_prev");
  return %("{
  "@env_setup"
  X2CCleanup $cleanup_name = {
    .fn = $callback_name,
    .env = "@env_arg"
  };
  x2c_cleanup_push(&$cleanup_name);
  "@body_code"
  int $previous = x2c_cleanup_exit_kind;
  x2c_cleanup_exit_kind = X2C_CLEANUP_EXIT_NORMAL;
  x2c_cleanup_leave(&$cleanup_name);
  x2c_cleanup_exit_kind = $previous;
}");
}

// Emit the selected transferring arm after detaching its registration. The
// retained error record stays borrowed through the arm and closes on every
// arm exit through the ordinary cleanup stack.
static List Emitter._filtered_catch(
  Emitter emitter, List records, String frame_name, String handle_name,
  List context, List final_code, List leave_stmt, String cleanup_guard) {
  String selected_name = emitter.fresh_name("catch_selected");
  Array arms = %[], int index = 0;
  foreach (List rec, records) {
    List (binders, pattern, body) = rec;
    (void) pattern;
    List handler_body = emitter._cleanup_emit(
      final_code, leave_stmt, cleanup_guard, body, context);
    List declarations = _make_catch_binders(binders, handle_name);
    arms.push(
      %(
      "if ($selected_name == $index) {"
        @declarations
        @handler_body
      "}"
    ));
    index++;
  }
  List guard = cleanup_guard ? %("$cleanup_guard = 1;") : %();
  List result = %("{"
    "int $selected_name = x2c_error_catch_selected($handle_name);"
    "x2c_error_catch_detach($handle_name);"
    "x2c_exception_mark_handled(&$frame_name);"
    @guard
    @{arms.list_free()}
  "}");
  return result;
}

static List Emitter._try_trailer(
  Emitter emitter, String cleanup_guard, List final_code, List leave_stmt) {
  String trailer_prev = emitter.fresh_name("cleanup_prev");
  if (cleanup_guard) {
    List final_guard =
      %("if ($cleanup_guard > 0) { " @final_code " }");
    return %(
      "if ($cleanup_guard >= 0) {
        int $trailer_prev = x2c_cleanup_exit_kind;
        x2c_cleanup_exit_kind = X2C_CLEANUP_EXIT_NORMAL;
        "@final_guard"
        x2c_cleanup_exit_kind = $trailer_prev;
        $cleanup_guard = -1;
        "@leave_stmt"
      }"
    );
  }
  return %(
    "int $trailer_prev = x2c_cleanup_exit_kind;
    x2c_cleanup_exit_kind = X2C_CLEANUP_EXIT_NORMAL;
    "@final_code"
    x2c_cleanup_exit_kind = $trailer_prev;
    "@leave_stmt
  );
}

static List Emitter._try(Emitter e, List ast, List context) {
  List (body, clause, finalizer) = ast.cdr();
  String frame_name = e.fresh_name("exception_frame");
  String handle_name = clause
    ? e.fresh_name("error_handler") : NULL;
  List final_code = NULL, String cleanup_guard = NULL;
  if (finalizer) {
    final_code = e._emit(%( $finalizer ), context);
    cleanup_guard = e.fresh_name("cleanup_guard");
  }
  if (clause)
    final_code = %(
      "x2c_error_catch_close($handle_name);"
      "$handle_name = NULL;"
      @final_code
    );
  List guard_decl = cleanup_guard ? %("volatile int " $cleanup_guard " = 1;")
                                  : %();
  List leave_stmt = %("x2c_exception_leave(&" $frame_name ");");
  List body_code = e._cleanup_emit(
    final_code, leave_stmt, cleanup_guard, body, context);
  body_code = cleanup_guard ? %("{" $cleanup_guard " = 1;" @body_code "}")
                            : body_code;
  List catch_block = NULL;
  if (clause)
    catch_block = e._filtered_catch(
      clause.cadr(), frame_name, handle_name, context,
      final_code, leave_stmt, cleanup_guard);
  List final_trailer =
    e._try_trailer(cleanup_guard, final_code, leave_stmt);
  if (!catch_block) {
    List exception_trailer =
      e._try_trailer(cleanup_guard, final_code, leave_stmt);
    catch_block = %("{" @exception_trailer "__builtin_unreachable();" "}");
  }
  else {
    List exception_trailer =
      e._try_trailer(cleanup_guard, final_code, leave_stmt);
    catch_block = %("{"
      "if (x2c_exception_is_error_target(&$frame_name))"
        @catch_block
      "else {"
        @exception_trailer
        "__builtin_unreachable();"
      "}"
    "}");
  }
  List pattern_decls = NULL, pattern_args = NULL;
  if (clause) {
    Array declarations = %[], arguments = %[];
    foreach (List rec, clause.cadr()) {
      List pattern = rec.cadr();
      if (pattern) {
        String name = e.fresh_name("catch_pattern");
        List emitted = e._emit(pattern, context);
        declarations.push(%("List $name = " @emitted ";"));
        arguments.push(%("List_var($name)"));
      }
      else arguments.push(_atom_intern("default"));
    }
    pattern_decls = declarations.list_free();
    pattern_args = e._commas(arguments.list_free());
  }
  List registration = clause ? %(
    @pattern_decls
    "ErrorHandler volatile $handle_name = x2c_error_catch_push("
      "&$frame_name, ${clause.cadr().list().len()}, " @pattern_args
    ");"
  ) : %();
  List result = %("{"
             "ExceptionFrame " $frame_name ";"
             @guard_decl
             @registration
             "x2c_exception_push(&" $frame_name ");"
             "if (!sigsetjmp(" $frame_name ".env, 0))" @body_code
             "else {"
               "x2c_exception_landed(&" $frame_name ");"
               @catch_block
             "}"
             @final_trailer
           "}");
  return result;
}

static String _c_string_literal(String value) {
  if (!value) value = "<unknown>";
  return %"\"${value.escape().replace("$$", "$")}\"";
}

static List Emitter._raise(
  Emitter e, Ast ast, Var cause, List arguments, List context) {
  List code = e._emit(cause, context);
  List arg_tokens = e._commas(e._emit(arguments, context));
  String site_name = e.fresh_name("error_site");
  List location = e.origin_location(e.origin);
  String file = location
    ? location.assoc(<file>).string() : e.compiler.filename;
  int line = location ? location.assoc(<line>).integer() : 0;
  String function = e.fn_name
    ? e.fn_name : %"<unknown>";
  String file_literal = _c_string_literal(file);
  String function_literal = _c_string_literal(function);
  List tail = arguments ? %("," @arg_tokens) : NULL;
  List terminal = ast.never_returns()
                ? %("__builtin_unreachable();") : NULL;
  return %("{"
    "static const X2CErrorSite " $site_name " = {"
      ".file = " $file_literal ","
      ".function = " $function_literal ","
      ".line = " $line
    "};"
    "x2c_error_raise_n(&" $site_name "," @code ","
      "${arguments.len() / 2}" @tail ");"
    @terminal
  "}");
}

/* Declare the named binders of a match case in source order. The wildcard
   binders `*` and `?` get no declaration. */

static List _make_local_binders(List binders, String values_name) {
  Array values = %[], int index = 0;
  foreach (Var binder, binders) {
    if (binder != <?> && binder != <*>) {
      String bvar = String.new(binder.str() + 1);
      String rhs = %"$values_name[$index]";
      values.push(
        binder.is_list_binder()
          ? %"List $bvar = Var_list($rhs);"
          : %"Var $bvar = $rhs;");
    }
    index++;
  }
  List result = values.list_free();
  return result;
}

static List _make_catch_binders(List binders, String handle_name) {
  Array values = %[], int index = 0;
  foreach (Var binder, binders) {
    String bvar = String.new(binder.str() + 1);
    String rhs = %"x2c_error_catch_capture($handle_name, $index)";
    values.push(
      binder.is_list_binder()
        ? %"List $bvar = Var_list($rhs);"
        : %"Var $bvar = $rhs;");
    index++;
  }
  List result = values.list_free();
  return result;
}

/* Label one arm so the switch can reach it directly. An arm whose pattern
   begins with a literal symbol only matches a subject beginning with that
   same symbol, so the arms in front of it may be jumped over; the second and
   later arms sharing a head take no label and are reached by falling through
   from the first. The first arm with no literal head can match anything, so
   it takes `default:` and ends the labelling. A failed arm still falls into
   everything after it, so arm order is unchanged. */

static List _match_arm_label(
  Emitter emitter, List pattern_ast, Array heads, int *labelling) {
  if (!*labelling) return NULL;
  Symbol head = emitter.match_pattern_head_symbol(pattern_ast);
  if (!head) {
    *labelling = 0;
    return %("default: ;");
  }
  if (heads.contains(head)) return NULL;
  heads.push(head);
  long code = head;
  return %("case $code: ;");
}

/* The pattern contains one Symbol and unique single-element captures.
   Keep the head check even under head dispatch: a failed arm falls through.
*/
static List _flat_match_condition(Symbol head, List binders) {
  Var literal = head;
  unsigned long long bits = literal.u64;
  Array condition = %[];
  condition.push(%"_x2c_match_expr && "
    + %"_x2c_match_expr->car.u64 == ${bits}ULL && "
    + "(_x2c_match_cursor = _x2c_match_expr->cdr, 1)");
  int index = 0;
  foreach (Var binder, binders) {
    condition.push(%"&& _x2c_match_cursor && "
      + %"(_x2c_match_values[$index] = _x2c_match_cursor->car, "
      + "_x2c_match_cursor = _x2c_match_cursor->cdr, 1)");
    index++;
  }
  condition.push("&& !_x2c_match_cursor");
  return condition.list_free();
}

/* Lower each match case to a conditional, in source order. */

static List Emitter._match_if(
  Emitter e, List ast, List context, int *dispatched) {
  Array values = %[], heads = %[], int labelling = 1;
  foreach (List rec, ast) {
    List (binders, pattern_ast, body_ast) = rec;
    List implicit_break = %("break;");
    match (body_ast)
      case %(guarded ?body): {
        body_ast = body;
        implicit_break = NULL;
      }
    Symbol flat_head = e.match_pattern_flat_head(pattern_ast, binders);
    int static_pattern = e.match_pattern_is_static(pattern_ast);
    List pattern = e._emit(pattern_ast, context);
    List body = e._emit(body_ast, context);
    List label = _match_arm_label(e, pattern_ast, heads, &labelling);
    if (label) values.push(label);
    if (pattern === %(*)) values.push(%($body @implicit_break));
    else if (flat_head) {
      List condition = _flat_match_condition(flat_head, binders);
      List declarations = _make_local_binders(binders, "_x2c_match_values");
      String closing = implicit_break ? "break; } }" : "} }";
      values.push(%("{ List _x2c_match_cursor;"
        "if (" @condition ") {" @declarations @body
        $closing));
    }
    else {
      String site_name = static_pattern
                       ? e.fresh_name("match_site")
                       : NULL;
      List site_declaration = static_pattern
                            ? %("static MatchCaptureSite $site_name;")
                            : NULL;
      List entry = static_pattern
                 ? %("x2c_match_site_try_capture(&" $site_name ",")
                 : %("x2c_match_try_capture(");
      List declarations = _make_local_binders(binders, "_x2c_match_values");
      values.push(
        %(
        @site_declaration
        "if (" @entry
          "_x2c_match_expr, List_var(" @pattern "),"
          "&_x2c_match_capture)) {"
        @declarations
        @body
        @implicit_break
        "}"
      ));
    }
  }
  if (labelling) values.push(%("default: break;"));
  *dispatched = heads.len() != 0;
  heads.free();
  List result = values.list_free();
  return result;
}

static List Emitter._match_cases(Emitter e, List ast, List context) {
  List (expr, cases) = ast.cdr();
  expr = e._emit(expr, context);
  int max_binders = 0;
  foreach (List rec, cases) {
    List binders = rec.car(), int count = binders.len();
    if (count > max_binders) max_binders = count;
  }
  // An arm reads only the values it bound, so the buffer names the two
  // fields it needs and Match fills in presence and order.
  List capture_declarations;
  if (max_binders) {
    String values_decl = %"Var _x2c_match_values[$max_binders];";
    String capture_decl =
      %"MatchCaptureBuffer _x2c_match_capture = { "
      + %".values = _x2c_match_values, .capacity = $max_binders };";
    capture_declarations = %($values_decl $capture_decl);
  }
  else
    capture_declarations = %(
      "MatchCaptureBuffer _x2c_match_capture = { 0 };"
    );
  // Arms are lowered into a real switch, so a "break" inside an arm leaves
  // that switch and must obey the same cleanup barrier as any other switch.
  int prev_break, prev_continue, dispatched;
  e._cleanup_barrier_enter(0, &prev_break, &prev_continue);
  List arms = e._match_if(cases, context, &dispatched);
  e._cleanup_barrier_leave(prev_break, prev_continue);
  // The subject's head symbol selects the first arm that can still match;
  // with no case labels every subject reaches the sole default arm.
  List selector = dispatched
    ? %("Var_symbol(car(_x2c_match_expr))") : %("0");
  return %("
  {
    List _x2c_match_expr = " $expr ";
    " @capture_declarations "
    switch (" @selector ") {
      " @arms "
    }
  }
");
}

static List Emitter._goto(Emitter e, Var label_ast, List context) {
  List label = e._emit(%($label_ast), context);
  List statement = %("goto" @label ";");
  String name = _cleanup_label_spelling(label_ast);
  Var target_var;
  if (!name || !e.label_paths ||
      !e.label_paths.try_get(name, &target_var)) {
    e.compiler.origin = e.origin;
    e.report_error(
      <emit>, "goto target label is not defined in this function",
      NULL, NULL);
  }
  List target = target_var, source = e.cleanup_path;
  int source_depth = source.len(), target_depth = target.len();
  List suffix = source;
  for (int i = source_depth; i > target_depth && suffix; i--)
    suffix = suffix.cdr();
  if (target_depth > source_depth || suffix != target) {
    e.compiler.origin = e.origin;
    e.report_error(
      <emit>, "goto cannot enter or cross a protected cleanup region",
      NULL, %("jump only within the same region or outward"));
  }
  return e._cleanup_wrap_goto(statement, target_depth);
}

static List Emitter._declare_stmt(
  Emitter e, List ast, List context) {
  if (e.volatile_names && _is_automatic_declaration(ast)) {
    List (type, bindings) = ast.cdr();
    if (_bindings_need_preservation(e, bindings) &&
        bindings.cdr().cdr()) {
      Array result = %[];
      bindings = e._preserve_bindings(bindings).cdr();
      foreach (List binding, bindings) {
        List declaration = %(declare $type (bindings $binding));
        _push_fragments(
          result, %(@{e._declare(declaration, context)} ";"));
      }
      return result.list_free();
    }
    ast = %(declare $type ${e._preserve_bindings(bindings)});
  }
  return %( @{e._declare(ast, context)} ";");
}

static List Emitter._decl_stmt(Emitter e, List ast, List context) {
  match (ast)
    case %(decl *declaration): ast = %(declare @declaration);
  if (e.volatile_names && _is_automatic_declaration(ast)) {
    List (type, bindings) = ast.cdr();
    ast = %(declare $type ${e._preserve_bindings(bindings)});
  }
  return e._declare(ast, context);
}

// Normalize #include directives to reference generated headers.
static List Emitter._preproc(Emitter emitter, List ast, List context) {
  String text = ast.cadr();
  text = text.rstrip("\n");
  if (!text.startswith("#include")) return cdr(ast);
  if (text.endswith(".x\"") || text.endswith(".x>")) {
    String last = text.split(" ").last(), stem = last.strip("\"<>")[:-3];
    String name = %"$stem.h", out = %"#include \"$name\"";
    return %( $out );
  }
  return %( $text );
}

/* Generic sequence emission visits sibling nodes from left to right because
   generated names, origins, and cleanup state change during the walk.
   Specialized forms choose their required construction order; for example,
   `_try` constructs the finalizer before the body and catch arms. This orders
   tokens, not C operand evaluation; only producer-marked forms such as
   `vseqcall` introduce runtime sequencing. Parser, transform, and generation
   produce every recognized AST shape, so the fallback handles only already
   C-shaped nodes. */
/* A left-leaning chain nests one (expr (op ...)) level per source term;
   walk the spine and build the token stream iteratively, folding from the
   right so each emitted piece is copied once. Descended levels drop
   `context` as the expr case does. A separate function keeps the
   spine arrays out of _emit's frame on every other recursion path. */
static List Emitter._op_spine(
  Emitter e, Var operator, Var left, Var right, List context) {
  Array operators = %[];
  Array rights = %[];
  defer operators.free();
  defer rights.free();
  Var op_item = operator, left_item = left, right_item = right;
  for (;;) {
    operators.push(op_item);
    rights.push(right_item);
    int deeper = 0;
    if (left_item is <list>)
      match (left_item)
        case %(expr ? (op ?next_operator ?next_left ?next_right)): {
          op_item = next_operator;
          left_item = next_left;
          right_item = next_right;
          deeper = 1;
        }
    if (!deeper) break;
  }
  int chained = (int) operators.len() > 1;
  List result = e._emit(%($left_item), chained ? NULL : context);
  Array pieces = %[];
  defer pieces.free();
  for (int i = (int) operators.len() - 1; i >= 0; i--) {
    pieces.push(operators[i]);
    pieces.push(e._emit(%(${rights[i]}), i ? NULL : context));
  }
  List tail = NULL;
  for (int i = (int) pieces.len() - 1; i >= 0; i--) {
    Var piece = pieces[i];
    if (piece is <list>) tail = piece.list().append(tail);
    else tail = cons(piece, tail);
  }
  return result.append(tail);
}

static List Emitter._emit(Emitter e, List ast, List context) {
  if (!ast) return ast;
  Var head = car(ast);
  if (head is <list>) {
    Array emitted = %[];
    defer emitted.free();
    while (ast && ast.car() is <list>) {
      emitted.push(e._emit(ast.car(), context));
      ast = ast.cdr();
    }
    List result = e._emit(ast, context);
    for (int i = (int) emitted.len() - 1; i >= 0; i--)
      result = cons(emitted[i], result);
    return result;
  }
  if (head is not <symbol>) return %( $head @{e._emit(cdr(ast), context)} );
  if (head != <typedef> &&
      (head.symbol().is_storage_class() ||
       head.symbol().is_type_qualifier() ||
       head.symbol().is_inline())) {
    Array prefix = %[];
    while (ast && ast.car() is <symbol>) {
      Symbol item = ast.car();
      if (item == <typedef> ||
          (!item.is_storage_class() && !item.is_type_qualifier() &&
           !item.is_inline()))
        break;
      if (item == <threaded>) prefix.push(%"_Thread_local");
      else prefix.push(ast.car());
      ast = ast.cdr();
    }
    return prefix.list_free().append(e._emit(ast, context));
  }
  match (ast) {
    case %(at ?origin ?inner): {
      int old_origin = e.origin;
      e.origin = origin.integer();
      List result = e._emit(inner, context);
      e.origin = old_origin;
      if (e.compiler.source_map)
        return %(src-at $origin @result src-at $old_origin);
      return result;
    }
    case %(varray *elements):
      return e._var_collection("Array", elements, context);
    case %(vmap *elements):
      return e._var_collection("Map", elements, context);
    case %(vpair ?key ?value): {
      List c_key = e._emit(%($key), context);
      List c_value = e._emit(%($value), context);
      return %(@c_key ", " @c_value);
    }
    case %(cons ?item ?tail): {
      List c_item = e._emit(%($item), context);
      List c_tail = e._emit(%($tail), context);
      return %("cons(" @c_item ", " @c_tail ")");
    }
    case %(append ?head_list ?tail): {
      List c_head = e._emit(%($head_list), context);
      List c_tail = e._emit(%($tail), context);
      return %("List_append(" @c_head ", " @c_tail ")");
    }
    case %(dotinit ?field ?value): {
      List c_field = e._emit(%($field), context);
      List c_value = e._emit(%($value), context);
      return %("." @c_field "=" @c_value);
    }
    case %(cast ?type ?expression): {
      List c_type = e._semantic_type(type);
      List c_expr = e._emit(%($expression), context);
      return %("(" @c_type ")" @c_expr);
    }
    case %(cache ?id): return %("_$id");
    case %(expr ? ?content): return e._emit(%($content), NULL);
    case %(postfix ?operator ?argument): {
      List c_arg = e._emit(%($argument), context);
      return %(@c_arg $operator);
    }
    case %(va-arg ?expression ?declaration): {
      List c_expr = e._emit(%($expression), NULL);
      List c_decl = e._emit(%($declaration), context);
      return %("va_arg(" @c_expr ", " @c_decl ")");
    }
    case %(call ?function ?arguments): {
      List c_fn = e._emit(%($function), NULL);
      List c_args = e._emit(%($arguments), NULL);
      return %(@c_fn "(" @c_args ")");
    }
    case %(index ?array ?index): {
      List c_array = e._emit(%($array), NULL);
      List c_index = e._emit(%($index), NULL);
      return %(@c_array "[" @c_index "]");
    }
    case %(op ?operator ?argument): {
      List c_arg = e._emit(%($argument), context);
      return %($operator @c_arg);
    }
    case %(op ?operator ?left ?right): {
      if (left is <list> && left.list().match(%(expr ? (op *))))
        return e._op_spine(operator, left, right, context);
      List c_left = e._emit(%($left), context);
      List c_right = e._emit(%($right), context);
      return %(@c_left $operator @c_right);
    }
    case %(op ?operator ?condition ?ontrue ?onfalse): {
      List c_cond = e._emit(%($condition), context);
      List c_then = e._emit(%($ontrue), context);
      List c_else = e._emit(%($onfalse), context);
      return %(@c_cond "?" @c_then ":" @c_else);
    }
    // Dynamic updates emit the lvalue once.
    case %(vcompound ?target ?operator ?value ?helper): {
      List c_target = e._emit(%($target), context);
      List c_op = e._emit(%($operator), context);
      List c_value = e._emit(%($value), context);
      return %($helper "(&(" @c_target "), " @c_op ", "
               @c_value ")");
    }
    case %(vpostfix ?target ?operator ?helper): {
      List c_target = e._emit(%($target), context);
      List c_op = e._emit(%($operator), context);
      return %($helper "(&(" @c_target "), " @c_op ")");
    }
    case %(vseqcall ? ?callee (args *arguments)):
      return e._sequenced_call(callee, arguments, context);
    case %(dstrvalue ?type ?result ?source ?temporary ?converted
           *statements):
      return e._destructure_value(
        type, result, source, temporary,
        converted, statements, context);
    case %(break):
      return e._cleanup_wrap_break(%("break;"));
    case %(continue):
      return e._cleanup_wrap_continue(%("continue;"));
    case %(if ?condition ?ontrue): {
      List c_cond = e._emit(%($condition), NULL);
      List c_then = e._emit(%($ontrue), NULL);
      return %("if" "(" @c_cond ")" @c_then);
    }
    case %(if ?condition ?ontrue ?onfalse): {
      List c_cond = e._emit(%($condition), NULL);
      List c_then = e._emit(%($ontrue), NULL);
      List c_else = e._emit(%($onfalse), NULL);
      return %("if" "(" @c_cond ")" @c_then
               "else" @c_else);
    }
    case %(while ?condition ?body): {
      List c_cond = e._emit(%($condition), NULL), int old_break, old_continue;
      e._cleanup_barrier_enter(1, &old_break, &old_continue);
      List c_body = e._emit(%($body), NULL);
      e._cleanup_barrier_leave(old_break, old_continue);
      return %("while" "(" @c_cond ")" @c_body);
    }
    case %(do ?body ?condition): {
      int old_break, old_continue;
      e._cleanup_barrier_enter(1, &old_break, &old_continue);
      List c_body = e._emit(%($body), NULL);
      e._cleanup_barrier_leave(old_break, old_continue);
      List c_cond = e._emit(%($condition), NULL);
      return %("do" @c_body "while"
               "(" @c_cond ")" ";");
    }
    case %(for ?initial ?condition ?increment ?body): {
      List c_init = e._emit(%($initial), context);
      List c_cond = e._emit(%($condition), context);
      List c_inc = e._emit(%($increment), context);
      int old_break, old_continue;
      e._cleanup_barrier_enter(1, &old_break, &old_continue);
      List c_body = e._emit(%($body), context);
      e._cleanup_barrier_leave(old_break, old_continue);
      return %("for" "(" @c_init ";" @c_cond ";"
               @c_inc ")" @c_body);
    }
    case %(switch ?expression ?body): {
      List c_expr = e._emit(%($expression), context);
      int old_break, old_continue;
      e._cleanup_barrier_enter(0, &old_break, &old_continue);
      List c_body = e._emit(%($body), context);
      e._cleanup_barrier_leave(old_break, old_continue);
      return %("switch" "(" @c_expr ")" @c_body);
    }
    case %(return):
      return e._cleanup_wrap_return(%("return;"));
    case %(return (!set ?expression (expr ? ?))): {
      List value = e._emit(%($expression), context);
      if (!e.cleanups.length) return %("return" @value ";");
      // Cleanup may mutate referenced state; save the return value first.
      String value_name = e.fresh_name("return_value");
      List declaration = e._semantic_name(e.return_type, value_name);
      List statement = e._cleanup_wrap_return(%("return" $value_name ";"));
      return %("{" @declaration "=" @value ";" @statement "}");
    }
    case %(goto ?label): return e._goto(label, context);
    case %(raise ?cause (args *arguments)):
      return e._raise(ast, cause, arguments, context);
    case %((!or fnmod func) ?parameters): {
      List c_params = e._emit(%($parameters), NULL);
      return %("(" @c_params ")");
    }
    case %(label ?name): {
      List c_name = e._emit(%($name), context);
      return %(@c_name ":");
    }
    case %(ident ?binding):
      return e._emit(%($binding), context);
  }
  switch (head.symbol()) {
    // x2c-specific constructs
    case <literal>:    return e._literal(ast, context);
    case <preproc>:    return e._preproc(ast, context);
    // Declarations
    case <bind>:       return e._bind(ast, context);
    case <declare>:    return e._declare_stmt(ast, context);
    case <decl>:       return e._decl_stmt(ast, context);
    case <enum>:       return e._enum(ast, context);
    case <falias>:     return e._foreign_alias(ast, context);
    case <function>:   return e._function(ast, context);
    case <param>:      return e._param(ast, context);
    case <struct>:     return e._aggregate(ast, context);
    case <typedef>: return %("typedef" @{e._emit(cdr(ast), context)} ";");
    case <union>:      return e._aggregate(ast, context);
    case <args>:       return e._args(ast, context);
    case <bindings>:
    case <params>:
      return e._commas(e._emit(cdr(ast), NULL));
    case <fields>:     return e._emit(cdr(ast), NULL);
    // Expressions
    case <block>:      return %("{" @{e._emit(cdr(ast), NULL)} "}");
    case <parens>:     return %("(" @{e._emit(cdr(ast), NULL)} ")");
    case <sizeof>: return %("sizeof" @{e._emit(cdr(ast), context)});
    // Statements
    case <case>: return %("case" ${e._emit(ast.cdr(), context)} ":");
    case <composite>: return %("{" @{e._emit(cdr(ast), context)} "}");
    case <default>:    return %("default:");
    case <defer>:      return e._defer(ast, context);
    case <empty>:      return %(";");
    case <try>:        return e._try(ast, context);
    case <stmnt>:      return %( @{e._emit(cdr(ast), context)} ";");
    case <matchcases>: return e._match_cases(ast, context);
    // Miscellaneous
    case <binding>:    return e._binding(ast, context);
    case <commas>: return e._commas(e._emit(cdr(ast), context));
    case <comment>:    return cdr(ast);
    case <nil>:        return %("NULL");
    case <space>:      return cdr(ast);
    // The one storage class whose x2c spelling is not its C spelling.
    case <threaded>:
      return %("_Thread_local" @{e._emit(cdr(ast), context)});
  }
  return %($head @{e._emit(cdr(ast), context)});
}

/** Emits a bound, typed, transform-normalized AST sequence as flat C tokens.
    Source mapping adds `src-at`/ID pairs consumed by the formatter.
    `compiler` must own the AST's binding facts and origins, and continue the
    translation session's shared generated-name state. This operation does not
    bind, transform, or choose header and source placement; generation supplies
    any added scaffolding in the same normalized grammar. It preserves the
    top-level AST sequence and advances generated-name counters as it allocates
    temporaries. Invalid `goto` placement reports through the compiler's
    `<emit>` diagnostic path. Returned canonical `List`s and `String`s are
    owned
    by pools active during emission; promote them before releasing those
    pools if the tokens must survive.
*/
List Compiler.emit(Compiler compiler, List ast) {
  struct Emitter state = {
    .compiler = compiler,
    .cleanups = Block.new(sizeof(Cleanup)),
    .break_stop = 0,
    .continue_stop = 0,
    .cleanup_path = NULL,
    .label_paths = NULL,
    .return_type = NULL,
    .origin = 0,
    .fn_name = NULL
  };
  Emitter emitter = &state;
  // flatten_all leaves no list element behind, so one pass is the fixed
  // point and a second call would only re-cons the whole unit to prove it.
  List code = emitter._emit(ast, NULL).flatten_all();
  state.cleanups.free();
  return code;
}
