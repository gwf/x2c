/*  emit.x -- emit C tokens from x2c ASTs

    Translates normalized ASTs into token `List`s for downstream flattening and
    formatting. One stack-local Emitter holds the current function's name,
    static objects, and native aliases, so emission is reentrant and a failed
    translation cannot contaminate later units. `cleanup.x` has already placed
    each cleanup region's statements on the exits that leave it.
*/

#pragma once

#include "compiler.x"
#pragma private
#include <stdlib.h>
#include <stdio.h>
#include "string.x"
#include "var.x"
#include "ast.x"
#include "format.x"
#include "cleanup.x"

// Per-emission state.
typedef struct Emitter {
  delegate Compiler compiler;
  int origin, String fn_name, List native_aliases;
  Array native_macros;
  Map static_objects;
  int static_support;
} *Emitter;

static List Emitter._commas(Emitter emitter, List lst) {
  (void) emitter;
  if (!lst.cdr()) return lst;
  Array result = [];
  int first = 1;
  foreach (Var item, lst) {
    if (!first) result.push(", ");
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
  params = emitter._emit(params);
  return emitter._declarator(%( @decl "(" @params ")"), mods);
}

static List Emitter._bitfield_declarator(
  Emitter emitter, List decl, List bits_list, List mods) {
  List size = emitter._emit(bits_list.cadr());
  decl = %( @decl ":" @size );
  return emitter._declarator(decl, mods);
}

static List Emitter._array_declarator(
  Emitter emitter, List decl, List array_list, List mods) {
  if (decl.type().is_pointer()) decl = _parens(decl);
  List size = array_list ? emitter._emit(array_list.cadr()) : NULL;
  decl = size ? %( @decl "[" @size "]") : %( @decl "[]");
  return emitter._declarator(decl, mods);
}

/* Lower each x2c `&` modifier to C `*` only as its declarator layer is
   folded. Do not recursively rewrite `mods`: nested `fnmod` parameter trees
   may be flat and must not consume one C stack frame per parameter. */
static List Emitter._pointer_declarator(Emitter e, List decl, List mods) {
  Var first = mods.car();
  if (first == <&>)
    return e._declarator(cons(<*>, decl), mods.cdr());
  if (first == <*> || Symbol.is_type_qualifier(first))
    return e._declarator(cons(first, decl), mods.cdr());
  return %( @mods @decl );
}

static List Emitter._declarator(Emitter e, List decl, List mods) {
  if (!mods) return decl;
  Var first = mods.car();
  if (first is <list>) {
    Type mod = first;
    if (mod.car() is <string>)
      return e._declarator(%( @decl @mod ), mods.cdr());
    if (mod.car() == <fnmod>)
      return e._function_declarator(decl, mod, mods.cdr());
    if (mod.is_array()) return e._array_declarator(decl, mod, mods.cdr());
    return e._bitfield_declarator(decl, mod, mods.cdr());
  }
  Symbol sym = first;
  switch (sym) {
    case <dim>: return e._array_declarator(decl, NULL, mods.cdr());
    case <*>: case <&>:
      return e._pointer_declarator(decl, mods);
    case <bitfield>:   return e._emit(mods.cdr());
    case <typedef>:
      return cons(<typedef>, e._declarator(decl, mods.cdr()));
  }
  if (sym.is_type_qualifier()) return e._pointer_declarator(decl, mods);
  return %( @mods @decl );
}

static List Emitter._bind(Emitter emitter, Ast ast) {
  List (ident, mods) = ast.cdr();
  ident = emitter._emit(ident);
  if (!mods) return ident;
  return emitter._declarator(ident, mods);
}

static List Emitter._param(Emitter e, List ast) {
  List (type, mods) = ast.cdr();
  List code = e._emit(type);
  mods = %( $mods );
  return code.append(e._emit(mods));
}

static List Emitter._args(Emitter emitter, List ast) {
  Array result = [];
  int first = 1;
  foreach (List argument, ast.cdr()) {
    List emitted = emitter._emit(argument);
    if (argument.match(%(expr ? (commas *)))) emitted = _parens(emitted);
    if (!first) result.push(", ");
    result.push(emitted);
    first = 0;
  }
  return result.list_free();
}

static List Emitter._declare(Emitter emitter, List ast) {
  List (type, bindings) = ast.cdr();
  type = emitter._emit(%( $type ));
  bindings = %( $bindings );
  return type.append(emitter._emit(bindings));
}

static List Emitter._function(Emitter e, List ast) {
  List (type, bindings, body) = ast.cdr();
  String old_fn = e.fn_name;
  List function_binding = bindings.cadr();
  e.fn_name = binding_identity_spelling(function_binding);
  Var defer_owner;
  if (e.semantic_binding_facts().try_get(
    %(defer-ownr $function_binding), &defer_owner))
    e.fn_name = defer_owner;
  type = e._emit(%( $type ));
  bindings = %( $bindings );
  body = %( $body );
  Map old_statics = e.static_objects;
  e.static_objects = {};
  List decl = e._emit(bindings), body_code = e._emit(body);
  e.fn_name = old_fn;
  e.static_objects = old_statics;
  return %(@type @decl @body_code);
}

// Emit a checked native-function alias without a wrapper object.
static List Emitter._foreign_alias(Emitter e, List ast) {
  List (declaration, native_binding) = ast.cdr();
  List bindings = declaration.caddr(), target = bindings.cadr().cadr();
  Type function_type = declaration.type_from_ast().declared();
  Type pointer_type = function_type.reference();
  List pointer = e._semantic_type(pointer_type);
  List native = e._emit(native_binding);
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

static List Emitter._enum(Emitter emitter, List ast) {
  List name = ast.type().tag(), body = ast.type().body().car();
  if (_is_gensym_tag(name) && !ast.type().is_enum_tag()) name = NULL;
  body = emitter._emit(body);
  body = emitter._commas(body);
  if (name) {
    if (body) return %( ${ast.car()} @name "{" @body "}");
    return %( ${ast.car()} @name );
  }
  return %( ${ast.car()} "{" @body "}");
}

static List Emitter._aggregate(Emitter emitter, List ast) {
  if (ast.type().is_aggregate_tag()) {
    Var alias = emitter.native_aliases.assoc(ast);
    if (alias is <list>) return emitter._emit(alias);
  }
  List tag = ast.type().tag();
  if (_is_gensym_tag(tag) && !ast.type().is_aggregate_tag()) tag = NULL;
  if (tag) tag = emitter._emit(tag);
  if (ast.type().is_aggregate_tag()) return %( ${ast.car()} @tag );
  List body = ast.type().body();
  body = emitter._emit(body);
  body = body.flatten_all();
  if (tag && body) return %( ${ast.car()} @tag "{" @body "}");
  if (tag) return %( ${ast.car()} @tag );
  return %( ${ast.car()} "{" @body "}");
}

static List Emitter._typedef(Emitter e, List ast) {
  List code = %("typedef" @{e._emit(ast.cdr())} ";");
  foreach (List declarator, ast.caddr().cdr()) {
    List binding = declarator.cadr();
    Var type;
    if (e.semantic_binding_facts().try_get(%(ntype $binding), &type))
      e.native_aliases = cons(%($type $binding), e.native_aliases);
  }
  return code;
}

static List Emitter._block(Emitter e, List ast) {
  $let(e.native_aliases, e.native_aliases)
    return %("{" @{e._emit(ast.cdr())} "}");
}

static List _atom_intern(String spelling) {
  String qq = "\"", text = %"$qq${spelling.escape().replace("$$", "$")}$qq";
  Atom atom = Atom.intern(spelling);
  if (atom is <symbol>) return %( "Symbol_var(Symbol_new($text))" );
  return %( "Atom_intern(String_new($text))" );
}

static List Emitter._literal(Emitter emitter, List ast) {
  (List type, String text, Var value) = ast.cdr();
  if (type === %("Var") && text == "void") return %("((void) 0, Void)");
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
  // C has no `0o` prefix; its octal spelling is a bare leading zero.
  if (text[0] == '0' && (text[1] == 'o' || text[1] == 'O'))
    text = "0" + String.new(text + 2);
  return %( $text );
}

static List Emitter._var_collection(
  Emitter emitter, String type, List elements) {
  if (!elements) return %("${type}_new()");
  List emitted = emitter._commas(emitter._emit(elements));
  String count = %"${elements.len()}";
  return %("${type}_update_n(${type}_new(), " $count ", " $emitted ")");
}

static List Emitter._binding(Emitter emitter, List ast) =>
  %(${emitter.emitted_binding_name(ast)});

static List Emitter._semantic_type(Emitter emitter, Type type) {
  List declaration = type.declaration_ast(NULL);
  return emitter._declare(declaration);
}

static List Emitter._semantic_name(
  Emitter emitter, Type type, String name) {
  List (base, mods) = type.declaration_parts();
  List declarator = emitter._declarator(%($name), mods);
  return %(${emitter._emit(base)} @declarator);
}

static int _static_case_entry(List node) {
  match (node) {
    case %((!or switch function expr declare typedef) *): return 0;
    case %((!or case default) *): return 1;
  }
  foreach (Var child, node)
    if (child is <list> && _static_case_entry(child)) return 1;
  return 0;
}

/* The native alias retains typedef and array qualifiers. Only a volatile
   object needs bytewise volatile reads; storage has no declared type yet. */
static List Emitter._static_copy(
  Emitter e, String alias, String guard, List source, String object) {
  String data = e.fresh_name("static_bytes");
  String index = e.fresh_name("static_byte");
  return %(
    "if (_Generic((" $alias "*)0, volatile" $alias "*: 1, default: 0)) {"
      "const volatile unsigned char *" $data "="
        "(const volatile unsigned char *)" @source ";"
      "for (size_t" $index "= 0;" $index "< sizeof(" $object ");"
           $index "++)"
        "((unsigned char *)" $guard ".payload)[" $index "] ="
          $data "[" $index "];"
    "} else memcpy(" $guard ".payload, (const void *)" @source ","
                   "sizeof(" $object "));"
  );
}

static List Emitter._local_static(Emitter e, List ast) {
  List declaration = ast.cadr(), body = ast.caddr();
  while (declaration.car() == <at>) {
    e.origin = declaration.cadr();
    declaration = declaration.caddr();
  }
  if (_static_case_entry(body)) {
    e.compiler.origin = e.origin;
    String note = "place the declaration before the switch "
                + "or within one case block";
    e.report_error(<emit>,
      "switch cannot bypass dynamic static initialization", NULL, %($note));
  }
  List (base, bindings) = declaration.cdr();
  Type declared_base = base;
  String base_name = e.fresh_name("static_type");
  List base_decl = e._semantic_name(declared_base.declared(), base_name);
  Array output = [];
  output.push(%("typedef" @base_decl ";"));
  String storage = declared_base.is_threaded() ? "static _Thread_local"
                                              : "static";
  foreach (List binding, bindings.cdr()) {
    List name, mods, initial = NULL;
    match (binding) {
      case %(op = (bind ?captured ?modifiers) ?value): {
        name = captured;
        mods = modifiers;
        initial = value;
      }
      case %(bind ?captured ?modifiers): {
        name = captured;
        mods = modifiers;
      }
    }
    Type type = mods.append(%($base_name));
    String spelling = e.emitted_binding_name(name);
    if (!initial ||
        !e.compiler.static_value_is_runtime(initial, e.static_objects)) {
      List native = e._semantic_name(type, spelling);
      List value = initial ? %("=" @{e._emit(initial)}) : NULL;
      output.push(%($storage @native @value ";"));
      continue;
    }
    e.static_support = 1;
    String alias = e.fresh_name("static_object_type");
    String pointer = e.fresh_name("static_object");
    String guard = e.fresh_name("static_guard");
    String cleanup = e.fresh_name("static_cleanup");
    String temporary = e.fresh_name("static_initial");
    int inferred = type.car() == <dim> || type.match(%((dim) *));
    if (inferred) {
      String probe = e.fresh_name("static_incomplete");
      String formal = e.fresh_name("static_input");
      List probe_decl = e._semantic_name(type.reference(), probe);
      output.push(%(@probe_decl ";"));
      e.static_objects[name] = probe;
      List operand = %(expr $type (cast $type $initial));
      List captured = %(
        "typedef __typeof__(" $formal ")" $alias ";"
        $storage "X2CStatic" $guard "= {0};"
        $alias "*" $pointer ";"
        "if (x2c_static_acquire(&" $guard ", sizeof(" $alias "),"
            "_Alignof(" $alias "),"
            ${declared_base.is_threaded() ? "1" : "0"} ")) {"
          $probe "=" $guard ".payload;"
          "X2CCleanup" $cleanup "= { .fn = x2c_static_abort,"
                                   ".env = &" $guard "};"
          "x2c_cleanup_push(&" $cleanup ");"
          @{e._static_copy(alias, guard, %("&" $formal), alias)}
          "x2c_static_commit(&" $guard ");"
          "x2c_cleanup_leave(&" $cleanup ");"
        "}"
        $pointer "=" $guard ".payload;"
      );
      output.push(e._initializer_macro(%(input ($formal $operand)), captured));
      e.static_objects[name] = pointer;
      continue;
    }
    List alias_decl = e._semantic_name(type, alias);
    e.static_objects[name] = pointer;
    List value = e._emit(initial);
    output.push(%(
      "typedef" @alias_decl ";"
      "_Static_assert(__builtin_constant_p(sizeof(" $alias ")),"
        "\"static object size must be constant\");"
      $storage "X2CStatic" $guard "= {0};"
      $alias "*" $pointer ";"
      "if (x2c_static_acquire(&" $guard ", sizeof(" $alias "),"
          "_Alignof(" $alias "),"
          ${declared_base.is_threaded() ? "1" : "0"} ")) {"
        $pointer "=" $guard ".payload;"
        "X2CCleanup" $cleanup "= { .fn = x2c_static_abort,"
                                 ".env = &" $guard "};"
        "x2c_cleanup_push(&" $cleanup ");"
        $alias $temporary "=" @value ";"
        @{e._static_copy(alias, guard, %("&" $temporary), temporary)}
        "x2c_static_commit(&" $guard ");"
        "x2c_cleanup_leave(&" $cleanup ");"
      "}"
      $pointer "=" $guard ".payload;"
    ));
  }
  output.push(e._emit(body));
  return output.list_free();
}

/* Runtime Match entry points whose second argument is the pattern. */
static String _match_site_entry(String name) {
  if (!name) return NULL;
  if (name == "List_match") return "x2c_match_site_match";
  if (name == "List_try_match") return "x2c_match_site_try_match";
  if (name == "List_search") return "x2c_match_site_search";
  if (name == "List_try_search") return "x2c_match_site_try_search";
  if (name == "List_match_replace") return "x2c_match_site_match_replace";
  if (name == "List_try_match_replace")
    return "x2c_match_site_try_match_replace";
  if (name == "List_search_replace") return "x2c_match_site_search_replace";
  return NULL;
}

/* A source-literal pattern is the same value on every call, so the call gets
   its own process-lifetime plan site and prepares once. A computed pattern
   keeps the ordinary entry, which prepares one plan per call. Only a direct
   global function binding identifies a runtime operation. Returns NULL
   when the call is not one of those operations or its pattern is computed. */
static List Emitter._match_site_call(
  Emitter e, Var function, Var arguments) {
  List binding = NULL;
  while (!binding && function is <list>) match (function) {
    case %(expr ? (parens ?inner)): function = inner;
    case %(expr ? (ident ?target)): binding = target;
    default: return NULL;
  }
  String name = binding_identity_spelling(binding);
  String entry = _match_site_entry(name);
  if (!entry) return NULL;
  Type type = NULL;
  List global = e.compiler.sym.resolve_global(%($name), &type);
  if (!global || !global.equal(binding) || !type.is_function())
    return NULL;
  List args = arguments;
  match (args)
    case %(args ? ?pattern *): {
      if (pattern is not <list> ||
          !e.match_pattern_is_static(pattern))
        return NULL;
      String site = e.fresh_name("match_site");
      List c_args = e._emit(%($arguments));
      return %("({ static MatchCaptureSite " $site ";"
               $entry "(&" $site "," @c_args "); })");
    }
  return NULL;
}

/* Transform has converted every `vseqcall` operand to its parameter type.
   C leaves call-argument evaluation order unspecified, so typed temporaries
   materialize these operands left-to-right before the protocol member call. */
static List Emitter._sequenced_call(Emitter e, Var callee, List arguments) {
  List c_fn = e._emit(%($callee));
  Array declarations = [], names = [];
  foreach (List argument, arguments)
    match (argument)
      case %(expr ?argument_type ?): {
        String name = e.fresh_name("protocol_arg");
        List declaration = e._semantic_name(
          argument_type, name);
        List value = e._emit(%($argument));
        declarations.push(%(@declaration "=" @value ";"));
        names.push(name);
      }
  List c_args = e._commas(names.list_free());
  return %("({" @{declarations.list_free()} @c_fn
           "(" @c_args ");" "})");
}

static List Emitter._destructure_value(
  Emitter e, Type type, List result, List source, List temporary,
  List converted, List statements) {
  /* The statement expression evaluates the source once, converts that saved
     value once, performs the producer-ordered assignments, and yields the
     original statically typed result. */
  String result_name = binding_identity_spelling(result);
  String temporary_name = binding_identity_spelling(temporary);
  List result_decl = e._semantic_name(type, result_name);
  List temporary_decl = e._semantic_name(%("List"), temporary_name);
  List c_src = e._emit(%($source));
  List c_repr = e._emit(%($converted));
  List c_stmts = e._emit(statements);
  return %("({" @result_decl "=" @c_src ";"
           @temporary_decl "=" @c_repr ";"
           @c_stmts $result_name ";" "})");
}


// Emit a callable defer region. The runtime record covers nonlocal transfer;
// the cleanup pass placed `cleanup` on ordinary and structured exits.
static List Emitter._defer(Emitter e, List ast) {
  List (body, env_binding, callback, records, record, cleanup) = ast.cdr();
  String cleanup_name = binding_identity_spelling(record);
  String callback_name = binding_identity_spelling(callback);
  List env_setup = NULL, env_arg = %("NULL");

  if (env_binding) {
    String env_type = binding_identity_spelling(env_binding);
    String env_name = e.fresh_name("defer_env"), Array initializers = [];
    foreach (List record, records) {
      String source = binding_identity_spelling(record.car());
      String field = binding_identity_spelling(record.caddr());
      initializers.push(%("." $field "=" "(const void *)" "&" $source));
    }
    List values = e._commas(initializers.list_free());
    env_setup = %("$env_type $env_name = {" @values "};");
    env_arg = %("&" $env_name);
  }

  List leave = e._emit(%( $cleanup ));
  List body_code = e._emit(%( $body ));
  return %("{
  "@env_setup"
  X2CCleanup $cleanup_name = {
    .fn = $callback_name,
    .env = "@env_arg"
  };
  x2c_cleanup_push(&$cleanup_name);
  "@body_code @leave"
}");
}

// Emit the selected transferring arm after detaching its registration. The
// retained error record stays borrowed through the arm and closes on every
// arm exit through the region's cleanup statements.
static List Emitter._filtered_catch(
  Emitter emitter, List records, String frame_name, String handle_name) {
  String selected_name = emitter.fresh_name("catch_selected");
  Array arms = [], int index = 0, count = records.len();
  foreach (List rec, records) {
    List binders = rec.car(), body = rec.caddr();
    List handler_body = emitter._emit(%( $body ));
    List declarations = _make_catch_binders(binders, handle_name);
    String branch = index == count - 1 ? (index ? "else" : "") :
                    index ? %"else if ($selected_name == $index)" :
                            %"if ($selected_name == $index)";
    arms.push(%("$branch {" @declarations @handler_body "}"));
    index++;
  }
  List selected = count > 1
    ? %("int $selected_name = x2c_error_catch_selected($handle_name);")
    : %();
  return %("{"
    @selected
    "x2c_error_catch_detach($handle_name);"
    "x2c_exception_mark_handled(&$frame_name);"
    @{arms.list_free()}
  "}");
}

static List Emitter._try(Emitter e, List ast) {
  List (body, clause, frame, handle, cleanup) = ast.cdr();
  String frame_name = binding_identity_spelling(frame);
  String handle_name = handle ? binding_identity_spelling(handle) : NULL;
  /* The pass built the statements that leave this region, including the
     run-once claim around a finalizer. Every path that leaves emits them. */
  List final_code = e._emit(%( $cleanup ));
  List body_code = e._emit(%( $body ));
  List catch_block = NULL;
  if (clause)
    catch_block = e._filtered_catch(clause.cadr(), frame_name, handle_name);
  /* Normal and handled paths share a trailer. The unhandled landing must
     remain visibly nonreturning to the native compiler. Avoid labels here:
     an enclosing finalizer can copy this emitted block into several exits. */
  List unhandled = %("{" @final_code "__builtin_unreachable();" "}");
  catch_block = catch_block ? %("{"
      "if (x2c_exception_is_error_target(&$frame_name))"
        @catch_block
      "else" @unhandled
    "}") : unhandled;
  /* Literal patterns retain one plan per arm. Interpolated patterns are
     prepared on each registration because their values may change. */
  List registration = %();
  if (clause) {
    String arms = e.fresh_name("catch_arms");
    String site = e.fresh_name("catch_site");
    String patterns = e.fresh_name("catch_patterns");
    Array declarations = [];
    int default_arm = -1, index = 0;
    String state = "ERROR_CATCH_PENDING";
    foreach (List rec, clause.cadr()) {
      List pattern = rec.cadr();
      if (pattern) {
        if (!e.match_pattern_is_static(pattern))
          state = "ERROR_CATCH_TRANSIENT";
        String name = e.fresh_name("catch_pattern");
        String slot = %"$patterns[$index]";
        List emitted = e._emit(pattern);
        declarations.push(
          %("List $name = " @emitted ";" "$slot = List_var($name);"));
      }
      else default_arm = index;
      index++;
    }
    String count = %"$index", String fallback = %"$default_arm";
    registration = %(
      "static MatchCaptureSite $arms[$count];"
      "static ErrorCatchSite $site = {"
      "  $arms, $fallback, $count, $state, -1 };"
      "Var $patterns[$count];"
      "if (x2c_error_catch_site_pending(&$site)) {"
        @{declarations.list_free()}
      "}"
      "ErrorHandler volatile $handle_name = x2c_error_catch_site_push("
        "&$frame_name, &$site, $patterns);"
    );
  }
  return %("{"
             "ExceptionFrame " $frame_name ";"
             @registration
             "x2c_exception_push(&" $frame_name ");"
             "if (!sigsetjmp(" $frame_name ".env, 0))" @body_code
             "else {"
               "x2c_exception_landed(&" $frame_name ");"
               @catch_block
             "}"
             @final_code
           "}");
}

static String _c_string_literal(String value) {
  if (!value) value = "<unknown>";
  return %"\"${value.escape().replace("$$", "$")}\"";
}

static List Emitter._raise(Emitter e, Ast ast, Var cause, List arguments) {
  List code = e._emit(cause);
  List arg_tokens = e._commas(e._emit(arguments));
  String site_name = e.fresh_name("error_site");
  List location = e.origin_location(e.origin);
  String file = location
    ? location.assoc(<file>) : e.compiler.filename;
  int line = location ? location.assoc(<line>) : 0;
  String function = e.fn_name
    ? e.fn_name : "<unknown>";
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
  Array values = [], int index = 0;
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
  return values.list_free();
}

static List _make_catch_binders(List binders, String handle_name) {
  Array values = [], int index = 0;
  foreach (Var binder, binders) {
    String bvar = String.new(binder.str() + 1);
    String rhs = %"x2c_error_catch_capture($handle_name, $index)";
    values.push(
      binder.is_list_binder()
        ? %"List $bvar = Var_list($rhs);"
        : %"Var $bvar = $rhs;");
    index++;
  }
  return values.list_free();
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
  if (head in heads) return NULL;
  heads.push(head);
  long code = head;
  return %("case $code: ;");
}

/* The pattern contains one Symbol and unique single-element captures.
   Keep the head check even under head dispatch: a failed arm falls through.
   A typed capture tests its tag the way the `is` operator does.
*/
static List _flat_match_condition(Symbol head, List tags) {
  Var literal = head;
  unsigned long long bits = literal.u64;
  Array condition = [];
  condition.push("_x2c_match_expr && "
    + %"_x2c_match_expr->car.u64 == ${bits}ULL && "
    + "(_x2c_match_cursor = _x2c_match_expr->cdr, 1)");
  int index = 0;
  foreach (Var tag, tags) {
    condition.push("&& _x2c_match_cursor ");
    if (tag is <symbol>)
      condition.push("&& Var_is(_x2c_match_cursor->car, "
        + %"${(unsigned long) tag.symbol()}) ");
    condition.push(%"&& (_x2c_match_values[$index] = _x2c_match_cursor->car, "
      + "_x2c_match_cursor = _x2c_match_cursor->cdr, 1)");
    index++;
  }
  condition.push("&& !_x2c_match_cursor");
  return condition.list_free();
}

/* Lower each match case to a conditional, in source order. A label stays in
   front of the conditional groups around its arm, so the switch still
   reaches later arms when the preprocessor removes that arm. */

static List Emitter._match_if(Emitter e, List ast, int *dispatched) {
  Array values = [], heads = [], int labelling = 1, opening = 0;
  List arms = NULL;
  foreach (List rec, ast) {
    if (rec.car() == <preproc>) {
      if (!arms) opening = values.len();
      arms = preproc_track_arms(arms, rec.cadr());
      values.push(e._emit(rec));
      continue;
    }
    List (binders, pattern_ast, body_ast) = rec;
    List implicit_break = %("break;");
    match (body_ast)
      case %(guarded ?body): {
        body_ast = body;
        implicit_break = NULL;
      }
    List flat_tags = NULL;
    Symbol flat_head =
      e.match_pattern_flat_head(pattern_ast, binders, &flat_tags);
    int static_pattern = e.match_pattern_is_static(pattern_ast);
    List pattern = e._emit(pattern_ast);
    List body = e._emit(body_ast);
    List label = _match_arm_label(e, pattern_ast, heads, &labelling);
    if (label) values.insert(arms ? opening++ : values.len(), label);
    if (pattern === %(*)) values.push(%($body @implicit_break));
    else if (flat_head) {
      List condition = _flat_match_condition(flat_head, flat_tags);
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
  return values.list_free();
}

static List Emitter._match_cases(Emitter e, List ast) {
  List (expr, cases) = ast.cdr();
  expr = e._emit(expr);
  int max_binders = 0;
  foreach (List rec, cases) {
    int count = rec.car() == <preproc> ? 0 : rec.car().list().len();
    if (count > max_binders) max_binders = count;
  }
  // An arm reads only the values it bound, so the buffer names the two
  // fields it needs and Match fills in presence and order.
  List capture_declarations;
  if (max_binders) {
    String values_decl = %"Var _x2c_match_values[$max_binders];";
    String capture_decl =
      "MatchCaptureBuffer _x2c_match_capture = { "
      + %".values = _x2c_match_values, .capacity = $max_binders };";
    capture_declarations = %($values_decl $capture_decl);
  }
  else
    capture_declarations = %(
      "MatchCaptureBuffer _x2c_match_capture = { 0 };"
    );
  int dispatched;
  List arms = e._match_if(cases, &dispatched);
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

static List Emitter._declare_stmt(Emitter e, List ast) =>
  %( @{e._declare(ast)} ";");

static List Emitter._decl_stmt(Emitter e, List ast) {
  match (ast)
    case %(decl *declaration): ast = %(declare @declaration);
  return e._declare(ast);
}

/* Native macro arguments expand once before C sees the selected conversion.
   Generated bodies have no source-map directives; the original argument keeps
   its ordinary mapping at the invocation and its original storage scope. */
static List Emitter._initializer_macro(Emitter e, List input, List body) {
  Buffer parameters = Buffer.new(0);
  foreach (List argument, input.cdr()) {
    if (parameters.len()) parameters.write_char(',');
    parameters.write(argument.car().str());
  }
  String formal = parameters.str_free();
  String hash = x2c_filename_hash(e.compiler.filename);
  String name = e.compiler.fresh_name(%"initializer_choice_$hash");
  String replacement;
  $let(e.compiler.source_map, 0) {
    List tokens = e._emit(body).flatten_all();
    String formatted = e.compiler.code_pretty_string(tokens, NULL);
    replacement = formatted.rstrip("\n").replace("\n", "\\\n");
  }
  String expanded = %"${name}_expanded";
  String definition = %"#define $expanded($formal) $replacement";
  e.native_macros.push(%($expanded $definition));
  e.native_macros.push(
    %($name "#define $name($formal) $expanded($formal)"));
  Array arguments = [];
  foreach (List argument, input.cdr()) {
    List emitted = e._emit(argument.cadr());
    arguments.push(%("(" @emitted ")"));
  }
  return %($name "(" @{e._commas(arguments.list_free())} ")");
}

static int _source_type_definition(List value) {
  Array pending = $auto([]);
  pending.push(value);
  while (pending.len()) {
    List node = pending.take_last();
    match (node) {
      case %(expr ? ?content): {
        pending.push(content);
        continue;
      }
      case %((!or struct union) ? (fields *)): return 1;
      case %((!or struct union) (fields *)): return 1;
      case %(enum ? (!is type list)): return 1;
    }
    foreach (Var child, node)
      if (child is <list>) pending.push(child);
  }
  return 0;
}

/* Expand source operands before moving native tag declarations ahead of the
   helper. An opaque call stays one operand, including its native quoting or
   token-pasting rules; x2c does not interpret declarations hidden inside
   it. */
static List Emitter._capture_source(
  Emitter e, List node, Array inputs, Array declarations) {
  match (node) {
    case %((!set ?kind (!or initval initcode))
           (!set ?input (input *)) *body): {
      List captured = e._capture_source(input, inputs, declarations);
      return %($kind $captured @body);
    }
    case %(expr ?type (!set ?content (composite *))): {
      List captured = e._capture_source(content, inputs, declarations);
      return %(expr $type $captured);
    }
    case %(expr ?type ?content): {
      int opaque = 0;
      match (content)
        case %(call (expr ?callable ?) ?): opaque = !callable.truth();
      if (opaque || !_source_type_definition(content)) {
        String formal = e.fresh_name("static_input");
        inputs.push(%($formal $node));
        return %(expr $type $formal);
      }
      List captured = e._capture_source(content, inputs, declarations);
      return %(expr $type $captured);
    }
    case %(!or ((!or struct union) ? (fields *))
               ((!or struct union) (fields *))
               (enum ? (!is type list))): {
      (Type definition, Type reference) = e.initializer_native_types(node);
      if (node.car() == <enum>) {
        reference = %(enum ${node.cadr()});
        match (node)
          case %(enum (gensym ? ?) ?body): {
            String name = e.fresh_name("static_enum");
            definition = %(enum $name $body);
            reference = %(enum $name);
          }
      }
      Array children = [];
      foreach (Var child, definition) {
        if (child is <list>)
          children.push(e._capture_source(child, inputs, declarations));
        else children.push(child);
      }
      definition = children.list_free();
      declarations.push(%(declare $definition (bindings (bind () ()))));
      return reference;
    }
    case %(call ?callee ?arguments): {
      List captured = e._capture_source(arguments, inputs, declarations);
      return %(call $callee $captured);
    }
  }
  Array children = [];
  foreach (Var child, node) {
    if (child is <list>)
      children.push(e._capture_source(child, inputs, declarations));
    else children.push(child);
  }
  return children.list_free();
}

static List Emitter._source_initializer(Emitter e, List function) {
  List (type, binding, body) = function.cdr();
  Array inputs = [], declarations = [];
  body = e._capture_source(body, inputs, declarations);
  List emitted = %(@{declarations.list_free()}
    (function $type $binding $body));
  return e._initializer_macro(%(input @{inputs.list_free()}), emitted);
}

static List Emitter._initializer_value(Emitter e, List ast) {
  List source = NULL;
  List functions = Ast.initializer_functions(ast, &source);
  if (functions)
    return e._emit(%(call (expr () (initval @functions)) (args $source)));
  List input = NULL;
  List cases = Ast.initializer_cases(ast, &input);
  if (input)
    return e._initializer_macro(input, %(initval @cases));
  List result = NULL;
  foreach (List choice, cases.reverse()) {
    (List condition, List path, Type type, List value) = choice;
    if (value.match(%(expr ? (composite *))))
      value = type ? %(expr $type (cast $type $value))
                   : %(expr (int) (literal (int) "0"));
    List emitted = e._emit(%($value));
    if (!result || !condition) result = emitted;
    else {
      List test = e._emit(%($condition));
      result = %("__builtin_choose_expr(" @test ","
                  @emitted "," @result ")");
    }
  }
  return result;
}

// Normalize #include directives to reference generated headers.
static List Emitter._preproc(Emitter emitter, List ast) {
  int angle = 0;
  String target = preproc_include_target(ast.cadr(), &angle);
  if (!target || !target.endswith(".x")) return ast.cdr();
  String out = %"#include \"${target.remove_suffix(".x")}.h\"";
  return %( $out );
}

/* Canonical AST nesting already states how operators group, but C text
   regroups by precedence, so emission is the one place that restores the
   nesting with parentheses. Every producer therefore builds operator nodes by
   structure alone and none of them tracks grouping.

   Larger levels bind more tightly, matching the C grammar: member access with
   postfix, then unary and cast, the binary levels, the conditional, and
   assignment. Level 0 means the emitter has no grouping rule for the
   operator, which leaves its text exactly as the other cases build it. */
static int _operator_precedence(Symbol operator) {
  switch (operator) {
    case <.>:    case <"->">:                   return 15;
    case <*>:    case </>:      case <%>:       return 13;
    case <+>:    case <->:                      return 12;
    case <"<<">: case <">>">:                   return 11;
    case <"<">:  case <">">:
    case <"<=">: case <">=">:                   return 10;
    case <==>:   case <!=>:                     return 9;
    case <&>:                                   return 8;
    case <^>:                                   return 7;
    case <|>:                                   return 6;
    case <&&>:                                  return 5;
    case <||>:                                  return 4;
  }
  return operator.is_assignment_op() ? 2 : 0;
}

enum {
  EMIT_CONDITIONAL = 3,
  EMIT_UNARY       = 14,
  EMIT_POSTFIX     = 15,
  EMIT_PRIMARY     = 16
};

/* The precedence of the C expression a node emits. Names, literals, calls,
   compound literals, statement expressions, and `parens` all emit text that
   already binds as tightly as a primary expression, so the default needs no
   grouping and adds no parentheses that C does not require. */
static int _emitted_precedence(Var node) {
  match (node) {
    case %(at ? ?inner):         return _emitted_precedence(inner);
    case %(expr ? ?content):     return _emitted_precedence(content);
    case %(op ?operator ? ?): {
      int level = _operator_precedence(operator);
      return level ? level : EMIT_PRIMARY;
    }
    case %(op ? ?):              return EMIT_UNARY;
    case %(op ? ? ? ?):          return EMIT_CONDITIONAL;
    case %((!or cast sizeof) *): return EMIT_UNARY;
    case %(postfix ? ?):         return EMIT_POSTFIX;
    case %(commas *):            return 1;
  }
  return EMIT_PRIMARY;
}

// The least tightly binding operand each side of a binary form accepts.
static int _left_operand_level(Symbol operator) {
  int level = _operator_precedence(operator);
  if (!level) return 0;
  return operator.is_assignment_op() ? level + 1 : level;
}

static int _right_operand_level(Symbol operator) {
  int level = _operator_precedence(operator);
  // A member name is not an expression, so it never takes parentheses.
  if (!level || operator == <.> || operator == <"->">) return 0;
  return operator.is_assignment_op() ? level : level + 1;
}

/* A node already stored as a List enters its own dispatch directly. Wrapping
   it in a one-element sequence would emit the same tokens through two more
   frames per operand, which the pinned chain stack budgets cannot spend. */
static List Emitter._operand(Emitter e, Var node, int level) {
  List code = node is <list> && !node.is_nil()
            ? e._emit(node) : e._emit(%($node));
  if (_emitted_precedence(node) < level) return _parens(code);
  return code;
}

/* Generic sequence emission visits sibling nodes from left to right because
   generated names and origins change during the walk.
   Specialized forms choose their required construction order; for example,
   `_try` constructs the finalizer before the body and catch arms. This orders
   tokens, not C operand evaluation; only producer-marked forms such as
   `vseqcall` introduce runtime sequencing. Parser, transform, and generation
   produce every recognized AST shape, so the fallback handles only already
   C-shaped nodes. */
/* A left-leaning chain nests one (expr (op ...)) level per source term;
   walk the spine and build the token stream iteratively, folding from the
   right so each emitted piece is copied once. A separate function keeps the
   spine arrays out of _emit's frame on every other recursion path. The walk
   stops where the nested operator needs parentheses, leaving that operand to
   the ordinary recursion. */
static List Emitter._op_spine(Emitter e, Var operator, Var left, Var right) {
  Array operators = $auto([]);
  Array rights = $auto([]);
  Var op_item = operator, left_item = left, right_item = right;
  int level = 0;
  for (;;) {
    operators.push(op_item);
    rights.push(right_item);
    level = _left_operand_level(op_item);
    int deeper = 0;
    if (_emitted_precedence(left_item) >= level)
      match (left_item)
        case %(expr ? (op ?next_operator ?next_left ?next_right)): {
          op_item = next_operator;
          left_item = next_left;
          right_item = next_right;
          deeper = 1;
        }
    if (!deeper) break;
  }
  List result = e._operand(left_item, level);
  Array pieces = $auto([]);
  for (int i = (int) operators.len() - 1; i >= 0; i--) {
    Symbol binary = operators[i];
    pieces.push(operators[i]);
    pieces.push(e._operand(rights[i], _right_operand_level(binary)));
  }
  List tail = NULL;
  for (int i = (int) pieces.len() - 1; i >= 0; i--) {
    Var piece = pieces[i];
    if (piece is <list>) tail = piece.list().append(tail);
    else tail = cons(piece, tail);
  }
  return result.append(tail);
}

static List Emitter._emit(Emitter e, List ast) {
  if (!ast) return ast;
  Var head = ast.car();
  if (head is <list>) {
    Array emitted = $auto([]);
    while (ast && ast.car() is <list>) {
      emitted.push(e._emit(ast.car()));
      ast = ast.cdr();
    }
    List result = e._emit(ast);
    for (int i = (int) emitted.len() - 1; i >= 0; i--)
      result = cons(emitted[i], result);
    return result;
  }
  if (head is not <symbol>) return %( $head @{e._emit(ast.cdr())} );
  if (head != <typedef> &&
      (head.symbol().is_storage_class() ||
       head.symbol().is_type_qualifier() ||
       head.symbol().is_inline())) {
    Array prefix = [];
    while (ast && ast.car() is <symbol>) {
      Symbol item = ast.car();
      if (item == <typedef> ||
          (!item.is_storage_class() && !item.is_type_qualifier() &&
           !item.is_inline()))
        break;
      if (item == <threaded>) prefix.push("_Thread_local");
      else prefix.push(ast.car());
      ast = ast.cdr();
    }
    return prefix.list_free().append(e._emit(ast));
  }
  match (ast) {
    case %(at ?origin ?inner): {
      int old_origin = e.origin;
      e.origin = origin;
      List result = e._emit(inner);
      e.origin = old_origin;
      if (e.compiler.source_map)
        return %(src-at $origin @result src-at $old_origin);
      return result;
    }
    case %(varray *elements):
      return e._var_collection("Array", elements);
    case %(vmap *elements):
      return e._var_collection("Map", elements);
    case %(vpair ?key ?value): {
      List c_key = e._emit(%($key));
      List c_value = e._emit(%($value));
      return %(@c_key ", " @c_value);
    }
    case %(cons ?item ?tail): {
      List c_item = e._emit(%($item));
      List c_tail = e._emit(%($tail));
      return %("cons(" @c_item ", " @c_tail ")");
    }
    case %(append ?head_list ?tail): {
      List c_head = e._emit(%($head_list));
      List c_tail = e._emit(%($tail));
      return %("List_append(" @c_head ", " @c_tail ")");
    }
    case %(c-assert ?condition ?message): {
      List c_condition = e._emit(%($condition));
      List c_message = e._emit(%($message));
      return %("_Static_assert(" @c_condition "," @c_message ");");
    }
    case %(initcode ?input ?body):
      return %(@{e._initializer_macro(input, body)} ";");
    case %(localinit ? ?): return e._local_static(ast);
    case %(sourceinit ?function):
      return e._source_initializer(function);
    case %(initval *): return e._initializer_value(ast);
    case %(indexinit ?index ?value): {
      List c_index = e._emit(%($index));
      List c_value = e._emit(%($value));
      String assign = value.car() == <dotinit> ||
                      value.car() == <indexinit> ? "" : " =";
      return %("[" @c_index "]" $assign @c_value);
    }
    case %(dotinit ?field ?value): {
      List c_field = e._emit(%($field));
      List c_value = e._emit(%($value));
      String assign = value.car() == <dotinit> ||
                      value.car() == <indexinit> ? "" : "=";
      return %("." @c_field $assign @c_value);
    }
    case %(cast ?type ?expression): {
      List c_type = e._semantic_type(type);
      List c_expr = e._operand(expression, EMIT_UNARY);
      return %("(" @c_type ")" @c_expr);
    }
    case %(cache ?id): return %("_$id");
    case %(expr ? ?content): return e._emit(%($content));
    case %(postfix ?operator ?argument): {
      List c_arg = e._operand(argument, EMIT_POSTFIX);
      return %(@c_arg $operator);
    }
    case %(generic ?control *associations): {
      List c_control = e._emit(%($control));
      Array rows = [];
      foreach (List association, associations) match (association) {
        case %(association default ?value):
          rows.push(%("default" ":" @{e._emit(%($value))}));
        case %(association ?type ?value): {
          List c_type = e._semantic_type(type);
          List c_value = e._emit(%($value));
          rows.push(%(@c_type ":" @c_value));
        }
      }
      List c_rows = e._commas(rows.list_free());
      return %("_Generic(" @c_control ", " @c_rows ")");
    }
    case %(va-arg ?expression ?declaration): {
      List c_expr = e._emit(%($expression));
      List c_decl = e._emit(%($declaration));
      return %("va_arg(" @c_expr ", " @c_decl ")");
    }
    case %(call ?function ?arguments): {
      List site_call = e._match_site_call(function, arguments);
      if (site_call) return site_call;
      List c_fn = e._operand(function, EMIT_POSTFIX);
      List c_args = e._emit(%($arguments));
      return %(@c_fn "(" @c_args ")");
    }
    case %(index ?array ?index): {
      List c_array = e._operand(array, EMIT_POSTFIX);
      List c_index = e._emit(%($index));
      return %(@c_array "[" @c_index "]");
    }
    case %(op ?operator ?argument): {
      List c_arg = e._operand(argument, EMIT_UNARY);
      return %($operator @c_arg);
    }
    case %(op ?operator ?left ?right): {
      if (left is <list> && left.list().match(%(expr ? (op *))))
        return e._op_spine(operator, left, right);
      Symbol binary = operator;
      List c_left = e._operand(left, _left_operand_level(binary));
      List c_right = e._operand(right, _right_operand_level(binary));
      return %(@c_left $operator @c_right);
    }
    /* Between `?` and `:` C accepts a complete expression, so only the
       condition and the false arm can regroup. */
    case %(op ?operator ?condition ?ontrue ?onfalse): {
      List c_cond = e._operand(condition, EMIT_CONDITIONAL + 1);
      List c_then = e._emit(%($ontrue));
      List c_else = e._operand(onfalse, EMIT_CONDITIONAL);
      return %(@c_cond "?" @c_then ":" @c_else);
    }
    // Dynamic updates emit the lvalue once.
    case %(vcompound ?target ?operator ?value ?helper): {
      List c_target = e._emit(%($target));
      List c_op = e._emit(%($operator));
      List c_value = e._emit(%($value));
      return %($helper "(&(" @c_target "), " @c_op ", "
               @c_value ")");
    }
    case %(vpostfix ?target ?operator ?helper): {
      List c_target = e._emit(%($target));
      List c_op = e._emit(%($operator));
      return %($helper "(&(" @c_target "), " @c_op ")");
    }
    case %(vseqcall ? ?callee (args *arguments)):
      return e._sequenced_call(callee, arguments);
    case %(dstrvalue ?type ?result ?source ?temporary ?converted
           *statements):
      return e._destructure_value(
        type, result, source, temporary, converted, statements);
    case %(break): return %("break;");
    case %(continue): return %("continue;");
    case %(if ?condition ?ontrue): {
      List c_cond = e._emit(%($condition));
      List c_then = e._emit(%($ontrue));
      return %("if" "(" @c_cond ")" @c_then);
    }
    case %(if ?condition ?ontrue ?onfalse): {
      List c_cond = e._emit(%($condition));
      List c_then = e._emit(%($ontrue));
      List c_else = e._emit(%($onfalse));
      return %("if" "(" @c_cond ")" @c_then
               "else" @c_else);
    }
    case %(while ?condition ?body): {
      List c_cond = e._emit(%($condition));
      List c_body = e._emit(%($body));
      return %("while" "(" @c_cond ")" @c_body);
    }
    case %(do ?body ?condition): {
      List c_body = e._emit(%($body));
      List c_cond = e._emit(%($condition));
      return %("do" @c_body "while"
               "(" @c_cond ")" ";");
    }
    case %(for ?initial ?condition ?increment ?body): {
      List c_init = e._emit(%($initial));
      List c_cond = e._emit(%($condition));
      List c_inc = e._emit(%($increment));
      List c_body = e._emit(%($body));
      return %("for" "(" @c_init ";" @c_cond ";"
               @c_inc ")" @c_body);
    }
    case %(switch ?expression ?body): {
      List c_expr = e._emit(%($expression));
      List c_body = e._emit(%($body));
      return %("switch" "(" @c_expr ")" @c_body);
    }
    case %(return): return %("return;");
    case %(return (!set ?expression (expr ? ?))): {
      List value = e._emit(%($expression));
      return %("return" @value ";");
    }
    case %(goto ?label): return %("goto" @{e._emit(%($label))} ";");
    case %(raise ?cause (args *arguments)):
      return e._raise(ast, cause, arguments);
    case %((!or fnmod func) ?parameters): {
      List c_params = e._emit(%($parameters));
      return %("(" @c_params ")");
    }
    case %(label ?name): {
      List c_name = e._emit(%($name));
      return %(@c_name ":");
    }
    case %(ident ?binding): {
      Var pointer;
      if (e.static_objects && e.static_objects.try_get(binding, &pointer))
        return %("(*" $pointer ")");
      return e._emit(%($binding));
    }
  }
  switch (head.symbol()) {
    // x2c-specific constructs
    case <adopt>: case <macrodef>: case <protocol>: return NULL;
    case <literal>:    return e._literal(ast);
    case <preproc>:    return e._preproc(ast);
    // Declarations
    case <bind>:       return e._bind(ast);
    case <declare>:    return e._declare_stmt(ast);
    case <decl>:       return e._decl_stmt(ast);
    case <enum>:       return e._enum(ast);
    case <falias>:     return e._foreign_alias(ast);
    case <function>:   return e._function(ast);
    case <param>:      return e._param(ast);
    case <struct>:     return e._aggregate(ast);
    case <typedef>:    return e._typedef(ast);
    case <union>:      return e._aggregate(ast);
    case <args>:       return e._args(ast);
    case <bindings>:
    case <params>:
      return e._commas(e._emit(ast.cdr()));
    case <fields>:     return e._emit(ast.cdr());
    // Expressions
    case <block>:      return e._block(ast);
    case <group>:      return e._emit(ast.cdr());
    case <parens>:     return %("(" @{e._emit(ast.cdr())} ")");
    case <sizeof>: return %("sizeof" @{e._emit(ast.cdr())});
    // Statements
    case <case>: return %("case" ${e._emit(ast.cdr())} ":");
    case <composite>: return %("{" @{e._emit(ast.cdr())} "}");
    case <default>:    return %("default:");
    case <defer>:      return e._defer(ast);
    case <empty>:      return %(";");
    case <try>:        return e._try(ast);
    case <stmnt>:      return %( @{e._emit(ast.cdr())} ";");
    case <matchcases>: return e._match_cases(ast);
    // Miscellaneous
    case <binding>:    return e._binding(ast);
    case <commas>: return e._commas(e._emit(ast.cdr()));
    case <comment>:    return ast.cdr();
    case <nil>:        return %("NULL");
    case <space>:      return ast.cdr();
    // The one storage class whose x2c spelling is not its C spelling.
    case <threaded>:
      return %("_Thread_local" @{e._emit(ast.cdr())});
  }
  return %($head @{e._emit(ast.cdr())});
}

/** Emits a bound, typed, transform-normalized AST sequence as flat C tokens.
    Source mapping adds `src-at`/ID pairs consumed by the formatter.
    `compiler` must own the AST's binding facts and origins, and continue the
    translation session's shared generated-name state. This operation does not
    bind, transform, or choose header and source placement; generation supplies
    any added scaffolding in the same normalized grammar. It preserves the
    top-level AST sequence and advances generated-name counters as it allocates
    temporaries. Returned canonical `List`s and `String`s are owned by pools
    active during emission; promote them before releasing those pools if the
    tokens must survive.
*/
List Compiler.emit(Compiler compiler, List ast) {
  struct Emitter state = {
    .compiler = compiler,
    .origin = 0,
    .fn_name = NULL,
    .native_macros = []
  };
  Emitter emitter = &state;
  // flatten_all leaves no list element behind, so one pass is the fixed
  // point and a second call would only re-cons the whole unit to prove it.
  List code = emitter._emit(ast).flatten_all();
  Array before = [], after = [];
  if (state.static_support)
    before.push("#include \"exception.h\"\n#include <string.h>");
  foreach (List entry, state.native_macros.list_free()) {
    (String name, String definition) = entry;
    before.push(definition);
    after.push(%"#undef $name");
  }
  return before.list_free().append(code).append(after.list_free());
}
