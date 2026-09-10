/*  generate.x -- generate C headers and source files

    Turns a normalized AST into formatted header and source files. It splits
    the header from the source, adds once-only translation-unit
    initialization and include guards, and writes the files. Filesystem
    failures retain their target and host error as compiler diagnostic
    notes.
*/
#pragma once
#include "compiler.x"
#pragma private

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "cache.x"
#include "format.x"
#include "transform.x"
#include "emit.x"
#include "utils.x"

// file utilities

static void _report_output_error(
  Compiler compiler, String fname, String message, int error) {
  String target = fname ? fname : %"<stdout>";
  List notes = %( "file:" $target );
  String err_note = %"errno: $error (${String.new(strerror(error))})";
  notes = cons(err_note, notes);
  compiler.report_error(<emit>, message, compiler.token, notes);
}

// Close both siblings before publishing either. A rename commits one complete
// file; the pair is not a transaction. Clean up before reporting: diagnostics
// may exit the process instead of unwinding the caller's cleanup stack.
static void _write_outputs(
  Compiler compiler, String paths[2], String contents[2]) {
  String temporaries[2] = { NULL, NULL };
  String message = NULL, fname = NULL;
  int error = 0;
  for (int i = 0; i < 2; i++) {
    fname = paths[i];
    File output = Stdout;
    if (fname) {
      String directory = x2c_path_dir(fname);
      int fd, serial = 0;
      do {
        temporaries[i] = %"$directory/.x2c-output.%ld.%d".printf(
          (long) getpid(), serial++);
        fd = open(temporaries[i], O_CREAT | O_EXCL | O_WRONLY, 0666);
      } while (fd < 0 && errno == EEXIST);
      if (fd < 0) {
        error = errno;
        temporaries[i] = NULL;
        message = "failed to open output file";
        break;
      }
      output = fdopen(fd, "w");
      if (!output) {
        error = errno;
        close(fd);
        message = "failed to open output file";
        break;
      }
    }
    if (output.puts(contents[i]) == EOF) {
      error = errno;
      message = "failed to write generated file";
    }
    if (output != Stdout && output.close() != 0 && !message) {
      error = errno;
      message = "failed to close generated file";
    }
    if (message) break;
  }
  if (!message) {
    for (int i = 0; i < 2; i++) {
      fname = paths[i];
      if (fname && rename(temporaries[i], fname)) {
        error = errno;
        message = "failed to replace generated file";
        break;
      }
    }
  }
  for (int i = 0; i < 2; i++)
    if (temporaries[i]) unlink(temporaries[i]);
  if (message) _report_output_error(compiler, fname, message, error);
}

// init staging

static List _make_init_call(String initializer, List guard) => %(
    if (expr (int) (op ! (expr (int) (ident $guard))))
       (stmnt (expr (void) (call $initializer (args) )))
  );

static List _make_shutdown_registration(Compiler compiler, String shutdown) {
  if (!shutdown) return NULL;
  List binding = compiler.sym.reference(%($shutdown), NULL);
  return %((
    stmnt
      (expr (void)
        (call "Scope_shutdown_hook"
          (args (expr ((func ((void))) void) (ident $binding)))))
  ));
}

static List _patch_func_with_init(
  List type, List bind, List statements, String initializer, List guard) => %(
    function $type $bind
    (block ${_make_init_call(initializer, guard)} @statements)
  );

/* Wrap the type-owned initializer with file and literal initialization.
   Cache graphs that require the initializer's own String/List canonicalizer
   are queued late; all other cache and static setup retains its pre-body
   order. */
static List _wrap_initializer_function(
  Compiler compiler, List type, List bind, List statements, List guard) {
  List shutdown = _make_shutdown_registration(compiler, compiler.fini_fn);
  return %(
    function $type $bind
    (block (if (expr (int) (ident $guard)) (return))
      (stmnt(expr (int) (op = (expr (int) (ident $guard))
          (expr (int) (literal (int) "1")))))
      @{compiler.early_inits}
      @{compiler.mid_inits}
      @statements
      @{compiler.late_inits}
      @shutdown
    )
  );
}

// Construct the synthetic file-level init function. The constructor
// attribute runs it in the root epoch, before main. Literal statics last
// for the whole process, so they must never be created inside a caller's
// allocation bracket. The lazy entry guards remain as the portable
// fallback.
static List _make_file_init_func(
  Compiler compiler, List guard, List initializer) {
  List shutdown = _make_shutdown_registration(compiler, compiler.fini_fn);
  return %(
    function (("__attribute__((constructor))") static void)
      ( bind $initializer (( fnmod (params (param (void) (bind () ()))))))
      ( block
        (stmnt (expr (void) (call "x2c_initialize_protocols" (args))))
        ( if (expr (int) (ident $guard)) (return) )
        (stmnt
          ( expr (int) (op = (expr (int) (ident $guard))
                             (expr (int) (literal (int) "1")))))
        @{compiler.early_inits}
        @{compiler.mid_inits}
        @{compiler.late_inits}
        @shutdown
      )
  );
}

// Install generated built-in protocol methods before any ordinary file
// constructor can create a String- or List-backed cache.
static List _wrap_protocol_initializer_function(
  Compiler compiler, List type, List bind, List statements) {
  List guard = compiler.sym.introduce("_x2c_protocol_guard_");
  return %(
    function $type $bind
      (block
        (declare (static int)
          (bindings (op = (bind $guard ()) (expr (int) (literal (int) "0")))))
        (if (expr (int) (ident $guard)) (return))
        (stmnt
          (expr (int)
            (op = (expr (int) (ident $guard))
                  (expr (int) (literal (int) "1")))))
        @{compiler.proto_inits}
        @statements)
  );
}

// Declare the guard that protects file initialization.
static List _make_init_guard(List guard) => %( declare (static int)
    ( bindings ( op = ( bind $guard ()) (expr (int) (literal (int) "0")))) );

static inline int _has_file_init_blocks(Compiler compiler) =>
  compiler.proto_inits.len() ||
         compiler.early_inits.len() ||
         compiler.late_inits.len() ||
         compiler.mid_inits.len() ||
         compiler.fini_fn;

static List _prepend_init_prelude(
  Compiler compiler, List result, List initGuard, List initFunc) {
  if (compiler.early_decls.len())
    foreach (Var declaration, compiler.early_decls)
      result = cons(declaration, result);
  if (initFunc) result = cons(initFunc, result);
  result = cons(initGuard, result);
  return result;
}

static int _is_protocol_bootstrap_function(String spelling) =>
  spelling == "x2c_initialize_protocols" ||
         spelling == "x2c_register_builtin_descriptor" ||
         spelling == "x2c_try_register_tagged_descriptor";

static void _collect_cache_function_refs(
  Var value, int caller, Map callers, int *uses_cache) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(cache ?): {
      *uses_cache = 1;
      return;
    }
    case %(ident (binding ?callee ?)): {
      int callee_identity = callee;
      List found = callers.contains(callee_identity)
                 ? callers[callee_identity].list() : NULL;
      callers[callee_identity] = cons(caller, found);
      return;
    }
  }
  foreach (Var child, node)
    _collect_cache_function_refs(child, caller, callers, uses_cache);
}

/* Find every function that directly or transitively reaches a source cache.
   A cache-only file patches only these entries. Its eager constructor
   already runs the initializers, and unrelated foundational calls then
   cannot recursively materialize literals during String/List pool setup. */
static Map _cache_reachable_function_ids(List source) {
  Map callers = %{}, reachable = %{}, Array queue = %[];
  foreach (List func, source)
    match (func)
      case %(!set ?definition
             (function ? (bind (binding ?identity ?) ?) ?)): {
        int function_identity = identity, uses_cache = 0;
        _collect_cache_function_refs(
          definition, function_identity, callers, &uses_cache);
        if (uses_cache) queue.push(function_identity);
      }
  for (int i = 0; i < queue.len(); i++) {
    int identity = queue[i];
    if (reachable.contains(identity)) continue;
    reachable[identity] = 1;
    if (callers.contains(identity))
      foreach (Var caller, callers[identity].list()) queue.push(caller);
  }
  queue.free();
  return reachable;
}

/* Consume the initialization state completed by cache setup. A synthetic file
   initializer calls protocol setup before early and middle work. A type-owned
   initializer wraps its own body between early/middle and late work, while the
   protocol initializer prepends its protocol queue. Shutdown registration is
   last in synthetic and type-owned initializers. initblock and initstmt
   markers do not reach generated output; the compiler's initialization
   queues hold those statements. */
static List _file_init(Compiler c, List source) {
  int hasInitBlocks = _has_file_init_blocks(c);
  String initializer = c.init_fn;
  if (!hasInitBlocks && !initializer) return source;

  List guard = c.sym.reference(%("_init_guard_"), NULL), initFunc = NULL;
  if (!initializer) {
    List file_init = c.sym.introduce("_file_init_");
    initFunc = _make_file_init_func(c, guard, file_init);
  }
  List initGuard = _make_init_guard(guard);
  String initializer_name = "_file_init_";
  if (initializer) initializer_name = initializer;
  int cache_only =
    !initializer && c.early_inits.len() &&
    !c.mid_inits.len() && !c.late_inits.len();
  Map cache_reachable_ids = cache_only
                          ? _cache_reachable_function_ids(source) : NULL;
  int inserted = 0, List result = NULL;

  foreach (List item, source) {
    match (item) {
      case %((!or initblock initstmt) *): continue;
      case %(!set ?function
             (function (!set ?type (*))
               (!set ?declarator
               (bind (binding ?identity ?spelling) ?))
               (block *statements))): {
        int function_identity = identity;
        if (!inserted) {
          result = _prepend_init_prelude(c, result, initGuard, initFunc);
          inserted = 1;
        }
        String name = spelling;
        if (name == "x2c_initialize_protocols")
          function = _wrap_protocol_initializer_function(
            c, type, declarator, statements);
        else if (initializer && name == initializer)
          function = _wrap_initializer_function(
            c, type, declarator, statements, guard);
        // Non-static entries initialize their static helpers.
        else if (!type.type().is_static() &&
                 !_is_protocol_bootstrap_function(name) &&
                 (!cache_only ||
                  cache_reachable_ids.contains(function_identity)))
          function = _patch_func_with_init(
            type, declarator, statements, initializer_name, guard);
        item = function;
      }
    }
    result = cons(item, result);
  }

  /* The prelude normally goes immediately before the first function, which
     calls it. A unit of only declarations has no such function. The
     constructor is then the only thing that runs the initializers the loop
     above dropped, so it goes after the declarations it assigns. */
  if (!inserted)
    result = _prepend_init_prelude(c, result, initGuard, initFunc);

  return result.reverse();
}

// header/source partitioning

static Type _remove_extern_from_type(Type type) =>
  type.filter(%!(elem) => elem != <extern>);

// Normalize declarations for header emission.
static List _header_declaration(List node, Type type, List bindings) {
  if (type.is_extern()) {
    bindings = bindings.match_replace(
      %(bindings (op = ?bind ?init)),
      %(bindings ?bind));
    return %( declare $type $bindings );
  }
  if (type.is_enum_tag_body() || type.is_aggregate_tag_body())
    return %(declare $type (bindings (bind () ())));
  return node;
}

// Normalize declarations that stay in the source file.
static List _source_declaration(List node, Type type, List bindings) {
  if (type.is_static()) return node;
  if (type.is_extern()) {
    type = _remove_extern_from_type(type);
    return %( declare $type $bindings );
  }
  return node;
}

// Promote inline functions into header prototypes.
static List _header_function(Type type, List bind, List body) {
  if (type.is_inline()) return %( function ( static @type ) $bind $body );
  return %( declare $type $bind );
}

// Keep only eligible functions in the source unit.
static List _source_function(List node, Type type) =>
  (!type.is_static() && type.is_inline()) ? NULL : node;

// Append generated nodes with consistent spacing.
static void _push_spaced(Array output, List code) {
  if (!code) return;
  output.push(code);
  output.push(%(space "\n"));
}

// The generator writes the header guard. Source pragmas serve only the CPP
// compatibility path and must not duplicate the generated directive.
static int _is_pragma_once(String content) =>
  content.strip(" \t\r\n") == "#pragma once";

// A positioned prototype remains visible to symbol collection, but the
// completed definition is what reaches generated C and H output.
static int _is_completed_function_prototype(Compiler compiler, List binding) {
  Var stored;
  if (!compiler.semantic_binding_facts().try_get(
    %(completion $binding), &stored))
    return 0;
  match (stored) case %(completed *): return 1;
  return 0;
}

static void _partition_function(
  Array header, Array source, Type type, List declarator, Ast body) {
  /* C sees only the prototype of a helper that always raises, so a caller
     whose last statement is that call looks like a missing return. Marking
     the type here reaches every generated form of the function. */
  if (body.never_returns()) type = %(("_Noreturn") @type);
  List function = %(function $type $declarator $body);
  if (type.is_static()) {
    _push_spaced(source, _source_function(function, type));
    return;
  }
  _push_spaced(header, _header_function(type, declarator, body));
  _push_spaced(source, _source_function(function, type));
}

static void _partition_declaration(
  Array header, Array source, List declaration, Type type, List bindings,
  int private) {
  if (private)
    _push_spaced(source, _source_declaration(declaration, type, bindings));
  else _push_spaced(header, _header_declaration(declaration, type, bindings));
}

static void _partition_alias(
  Array header, Array source, List alias, Type type) {
  _push_spaced(type.is_static() ? source : header, alias);
}

static void _partition_preproc(
  Array header, Array source, List node, String content, int *private) {
  if (_is_pragma_once(content)) return;
  if (content.contains("pragma public")) *private = 0;
  else if (content.contains("pragma private")) *private = 1;
  else (*private ? source : header).push(node);
}

/* Partition a normalized unit without changing source order. Non-inline
   public functions publish a header declaration and keep their body in the
   source; public inline definitions remain header-only. A function definition,
   static declaration, or foreign alias begins source-private output until an
   explicit public pragma changes visibility. */
/* True when `node` spells the typedef name `name` anywhere, as a
   single-string type atom such as `("Point")`. */
static int _mentions_type(List node, String name) {
  if (!node) return 0;
  if (node.car() is <string> && !node.cdr()) return node.car() == name;
  for (List rest = node; rest; rest = rest.cdr())
    if (rest.car() is <list> && _mentions_type(rest.car(), name)) return 1;
  return 0;
}

static String _typedef_name(List typedef_node) {
  match (typedef_node) {
    case %(typedef ? (bindings (bind (binding ? ?name) ?) *)): return name;
    case %(typedef ? (bindings (bind (?name) ?) *)): return name;
  }
  return NULL;
}

/* A typedef that follows a function definition is source-private unless a
   later header item names it and no earlier header typedef already
   declares that name; a public prototype must be able to spell its
   parameter types, while an opaque forward typedef keeps a private body
   private. Markers hold each such typedef's position in both files until
   the whole unit has been partitioned. */
static List _resolve_typedef_markers(Array items, Array pending, int header) {
  Array output = %[];
  int count = items.len();
  for (int i = 0; i < count; i++) {
    Var item = items[i];
    match (item) {
      case %(pending ?index): {
        int at = index.int();
        List entry = pending[at];
        String name = entry.car(), List node = entry.cadr();
        int promoted = entry.caddr().int();
        if (header) {
          int declared = 0;
          for (int j = 0; j < i && !declared; j++)
            declared = items[j] is <list> &&
                       _typedef_name(items[j].list()) == name;
          for (int j = i + 1; j < count && !promoted && !declared; j++)
            promoted = items[j] is <list> &&
                       _mentions_type(items[j].list(), name);
          pending[at] = %($name $node $promoted);
        }
        if (promoted == header) output.push(node);
        continue;
      }
    }
    output.push(item);
  }
  return output.list_free();
}

static List _header_and_source(Compiler compiler, List ast) {
  Array header = %[], source = %[], pending = %[], int private = 0;
  foreach (Ast node, ast) {
    match (node) {
      case %((!or protocol adopt macrodef) *): continue;
      case %(typedef ? (bindings *)): {
        String name = private ? _typedef_name(node) : NULL;
        if (!name) {
          (private ? source : header).push(node);
          continue;
        }
        List marker = %(pending ${pending.len()});
        pending.push(%($name $node 0));
        header.push(marker);
        source.push(marker);
        continue;
      }
      case %(function (!set ?type (*)) ?declarator
             (!set ?body (block *))): {
        _partition_function(header, source, type, declarator, body);
        private = 1;
        continue;
      }
      case %(!set ?declaration
             (declare (!set ?type (*))
               (!set ?bindings (bindings *)))): {
        match (bindings)
          case %(bindings (bind (!set ?binding (*)) ?)):
            if (_is_completed_function_prototype(compiler, binding)) continue;
        Type declaration_type = type;
        if (declaration_type.is_static()) private = 1;
        _partition_declaration(
          header, source, declaration, declaration_type, bindings, private);
        continue;
      }
      case %(!set ?alias (falias (declare (!set ?type (*)) ?) ?)): {
        _partition_alias(header, source, alias, type);
        private = 1;
        continue;
      }
      // The consumer's types name the package's, so the include belongs to
      // the header; the source reaches it through the generated header.
      case %(import ?unit *): {
        header.push(%(preproc "#include \"${unit.string()}.x\""));
        header.push(%(space "\n"));
        continue;
      }
      case %(preproc ?content): {
        _partition_preproc(header, source, node, content, &private);
        continue;
      }
    }
    (private ? source : header).push(node);
  }
  List header_list = _resolve_typedef_markers(header, pending, 1);
  List source_list = _resolve_typedef_markers(source, pending, 0);
  return %( $header_list $source_list );
}

static int _declaration_references_static_function(Var value, Map bindings) {
  if (value is <symbol>) return value == <fnmod> || value == <func>;
  if (value is not <list> || value.is_nil()) return 0;
  List node = value;
  match (node)
    case %(ident (!set ?binding (binding ? ?))):
      if (bindings.contains(binding)) return 1;
  foreach (Var child, node)
    if (_declaration_references_static_function(child, bindings)) return 1;
  return 0;
}

static List _declaration_binding(List declarator) {
  match (declarator) {
    case %(bind (!set ?binding (binding ? ?)) ?): return binding;
    case %(op = (!set ?binding (bind (binding ? ?) ?)) ?): return binding;
  }
  return NULL;
}

static void _collect_local_function_bindings(Var value, Map bindings) {
  if (value is not <list> || value.is_nil()) return;
  List node = value;
  match (node) {
    case %(function ? (!set ?declarator (bind (binding ? ?) ?)) ?): {
      bindings[_declaration_binding(declarator)] = 1;
      return;
    }
    case %(declare ? (!set ?declarator (bind (binding ? ?) ?))): {
      if (node.type_from_ast().is_function())
        bindings[_declaration_binding(declarator)] = 1;
      return;
    }
    case %(declare (!set ?base (*)) (bindings *declarators)): {
      foreach (List declarator, declarators) {
        List binding = _declaration_binding(declarator);
        if (!binding) continue;
        List declaration = %(declare $base (bindings $declarator));
        if (declaration.type_from_ast().is_function()) bindings[binding] = 1;
      }
      return;
    }
  }
  foreach (Var child, node) _collect_local_function_bindings(child, bindings);
}

/* One complete unit walk per generation, so it keeps the manual worklist.
   A Func visit callback's dynamic call per node cost ~2% of
   self-translation. Pending sibling suffixes wait on `resume` to stay off
   the C stack. */
static void _collect_external_function_prototypes(
  Compiler compiler, Var value, Map locals, Map seen, Array prototypes) {
  if (value is not <list> || value.is_nil()) return;
  Array resume = %[];
  defer resume.free();
  List node = value;
  for (;;) {
    match (node) {
      case %(expr ? (ident (!set ?binding (binding ? ?)))): {
        String spelling = binding_identity_spelling(binding);
        Type type = NULL;
        List global = spelling
          ? compiler.sym.resolve_global(%($spelling), &type) : NULL;
        if (global && List.equal(global, binding) && type.is_function() &&
            !locals.contains(global) && !seen.contains(global)) {
          seen[global] = 1;
          prototypes.push(type.declaration_ast(global));
        }
      }
    }
    List rest = node;
    for (;;) {
      while (!rest) {
        if (!resume.len()) return;
        rest = resume.take_last();
      }
      Var child = rest.car();
      rest = rest.cdr();
      if (child is <list> && !child.is_nil()) {
        if (rest) resume.push(rest);
        node = child;
        break;
      }
    }
  }
}

static List _static_prototypes(Compiler compiler, List source, List header) {
  Array declarations = %[], decls = %[], consumers = %[], prelude = %[];
  Array prototypes = %[], externals = %[], output = %[];
  Map static_functions = %{}, local_functions = %{}, external_seen = %{};
  _collect_local_function_bindings(header, local_functions);
  _collect_local_function_bindings(source, local_functions);
  _collect_external_function_prototypes(
    compiler, source, local_functions, external_seen, externals);
  int output_started = 0;
  foreach (List node, source) {
    match (node) {
      case %((!or declare typedef) *): {
        declarations.push(node);
        continue;
      }
      case %(preproc ?content): {
        String directive = content.string().strip(" \t\r\n");
        if (directive.startswith("#include") ||
            directive.startswith("#define")) {
          prelude.push(node);
          continue;
        }
      }
      case %(function ?type
             (!set ?signature (bind (!set ?binding (binding ? ?)) ?)) ?): {
        output.push(node);
        output_started = 1;
        if (type.type().is_static()) {
          static_functions[binding] = 1;
          prototypes.push(%(declare $type $signature));
        }
        continue;
      }
    }
    if (!output_started) prelude.push(node);
    else output.push(node);
  }
  foreach (List declaration, declarations.list_free())
    if (declaration.car() == <declare> &&
        _declaration_references_static_function(
          declaration, static_functions)) consumers.push(declaration);
    else decls.push(declaration);
  List decl_list = decls.list_free(), consumer_list = consumers.list_free();
  List prelude_list = prelude.list_free();
  List external_list = externals.list_free();
  List prototype_list = prototypes.list_free();
  List output_list = output.list_free();
  return %(
    @decl_list
    @prelude_list
    @external_list
    @prototype_list
    @consumer_list
    @output_list
  );
}

// formatting

// Emit the standard auto-generated banner.
static List _header(void) => %(
    (comment "/* auto-generated by x2c.  Do not edit! */")
    (space "\n")
    (space "\n")
  );

static List _header_guard(List content, String guard) => %(
    (preproc "#pragma once")
    (space "\n\n")
    (preproc "#ifndef __GUARD_0x${guard}__")
    (space "\n")
    (preproc "#define __GUARD_0x${guard}__")
    (space "\n\n")
    @content
    (space "\n")
    (preproc "#endif /* __GUARD_0x${guard}__ */")
    (space "\n")
  );

static List _include_directive(String fname) =>
  %((preproc "#include \"$fname\"") (space "\n") (space "\n"));

static List _vertical_spacing(List code) {
  Array values = %[];
  foreach (Var elem, code) {
    Symbol kind = elem.car();
    if (kind == <space>) continue;
    values.push(elem);
    values.push(%(space "\n"));
  }
  List result = values.list_free();
  return result;
}

static int _has_runtime_include(List content) {
  foreach (List unit, content) {
    if (!unit) continue;
    Var (kind, payload) = unit;
    if (kind != <preproc>) continue;
    String text = payload.string().strip(" \t\r\n");
    if (text == "#include \"x2c.x\"" || text == "#include <x2c.x>") return 1;
  }
  return 0;
}

static List _include_guard(
  Compiler compiler, List content, String filename) {
  if (compiler.runtime_inc && !_has_runtime_include(content))
    content = cons(%(preproc "#include \"x2c.x\""), content);
  String guard = x2c_filename_hash(filename), List header = _header();
  List guarded_code = _header_guard(content, guard);
  return %( @header @guarded_code );
}

// Insert the generated header include at the top of the source file.
static List _primary_include(Compiler compiler, List content) {
  String xname = compiler.filename.split("/").last();
  if (xname.endswith(".x")) xname = xname[:-2];
  String hname = %"${xname}h", List header = _header();
  List include = _include_directive(hname);
  List error = ast_contains_head(content, <raise>)
             ? _include_directive("error.h") : NULL;
  return %( @header @include @error @content );
}

// source finalization

// Inject compiler bootstrap invocation into main when present.
static List _modify_main(Compiler compiler, List source) {
  List initializer = compiler.sym.reference(%("x2c_initialize"), NULL);
  return source.map(%!(List unit) => {
    match (unit)
      case %(function ?rtype
             (bind (!set ?binding (*)) ?params)
             (block *vbody)):
        if (binding_identity_spelling(binding) == "main")
          return %(
            function $rtype (bind $binding $params)
            (block
              (stmnt (expr (void) (call
                (expr ((func ((void))) void) (ident $initializer))
                (args (expr (void) ())))))
              @vbody)
          );
    return unit;
  });
}

// public entry point

/** Writes the generated C header and source for one lowered translation unit.
    `ast` must be the normalized result of `transform_ast` for this compiler;
    its filename, symbols, binding facts, cache keys, and initialization state
    must still describe that same unit. `dir` must already exist. Generation
    partitions the AST, materializes caches and once-only initialization,
    performs the generation-phase source transform, and writes or replaces
    `<dir>/<source-stem>.h` and `.c`. It appends generated bindings and
    initialization work to the compiler and is not idempotent. Both files
    are closed before individual renames replace their destinations; failure
    can leave only the header replaced, but never a partial file. Failures
    are reported as `emit` diagnostics.
*/
void generate_code(Compiler c, List ast, String dir) {
  ast = ast.filter(
    %!(unit) => !unit.list().match(%((!or space comment empty) *)));

  List (header, source) =
    _header_and_source(c, ast);
  String hash = x2c_filename_hash(c.filename);
  (header, source) = c.setup_cache_init(
    header, source,
    %"_x2c_hcache_${hash}_",
    %"_x2c_hcache_guard_$hash",
    %"_x2c_hcache_init_$hash");

  List header_declarations = header;
  header = _vertical_spacing(header);
  header = _include_guard(c, header, c.filename);
  header = c.emit(header);

  source = _file_init(c, source);
  source = _static_prototypes(c, source, header_declarations);
  source = _vertical_spacing(source);
  source = _primary_include(c, source);
  source = _modify_main(c, source);
  source = c.transform(source);
  source = c.emit(source);

  String basename =
    %"${dir.rstrip(%"/")}/${x2c_path_stem(c.filename)}";
  String hfile = %"$basename.h", cfile = %"$basename.c";
  String header_text = c.code_pretty_string(header, hfile);
  String source_text = c.code_pretty_string(source, cfile);
  String paths[2] = { hfile, cfile };
  String contents[2] = { header_text, source_text };
  _write_outputs(c, paths, contents);
}
