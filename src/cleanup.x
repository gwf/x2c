/*  cleanup.x -- what a cleanup region runs, and which exits run it

    Copyright (c) 2026 Gary William Flake.

    `defer` and `try` regions reach this pass as the forms `transform.x`
    produced. It names each region's runtime record, builds the statements
    that leave the region, and runs them on every exit that leaves it: the
    region's own end, a `return`, a `break` or `continue` that leaves the
    construct, and an outward `goto`. `emit.x` prints the frames, records,
    and statements this pass decided on.

    A `break` or `continue` only transfers inside its own loop or switch, so
    it leaves the regions opened inside that construct and no others. A
    `return` leaves every open region, after saving its value, because
    cleanup may change what the expression read. A `goto` leaves exactly the
    regions between it and its label, and entering a region it did not open
    is rejected here.
*/

#pragma once
#include "compiler.x"

#pragma private
$(import "../src/ast-rewrite.xmacro")

#include "ast.x"
#include "type.x"

/* The runtime types a region's record and frame have. */
static String _frame_type = "ExceptionFrame";
static String _record_type = "X2CCleanup";
static String _handler_type = "ErrorHandler";

/* The walk state for one function body. */
typedef struct Walk {
  Compiler compiler;
  Array regions;
  int break_stop, continue_stop, origin;
  Map labels;
  Type return_type;
} *Walk;

static List _address_of(String spelling, List binding) {
  Type type = %(($spelling));
  return %(expr ${type.reference()} (op & (expr $type (ident $binding))));
}

/* One native call on a region's record or frame, as a statement. */
static List _region_call(String function, String type, List binding) =>
  %(stmnt (expr (void)
    (call $function (args ${_address_of(type, binding)}))));

/* Introduce a name this pass owns. The emitted declaration spells this
   binding, so the record a region pushes and the record its exits leave are
   one name by construction. */
static List _region_binding(Compiler compiler, String role) =>
  compiler.sym.introduce(compiler.fresh_name(role));

/* The statements that leave a `defer` region: the runtime unlinks the
   record and calls its thunk. */
static List _defer_cleanup(List record) =>
  %(${_region_call("x2c_cleanup_leave", _record_type, record)});

/* The first label a finalizer defines, or NULL. The statements that leave a
   region run on every path that leaves it, so a label among them would be
   defined once per path. */
static Var _finalizer_label(Var value, int origin, int *at) {
  Array pending = $auto([value]), origins = $auto([origin]);
  while (pending.len()) {
    Var current = pending.take_last();
    int here = origins.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    match (node) {
      case %(function *): continue;
      case %(expr *): continue;
      case %(at ?(int inner) ?wrapped): {
        pending.push(wrapped);
        origins.push(inner);
        continue;
      }
      case %(label ?name *): {
        *at = here;
        return name;
      }
    }
    foreach (Var child, node) {
      pending.push(child);
      origins.push(here);
    }
  }
  return NULL;
}

/* The statements that leave a `try` region, in the order the frame
   requires: a catch clause closes and clears its handler, a finalizer runs
   under the frame's run-once claim, and the frame leaves last. Claiming also
   retires the landing, so a `raise` from the finalizer reaches the enclosing
   frame instead of re-entering this one and looping. */
static List _try_cleanup(
  List frame, List handle, List finalizer, int has_clause) {
  Array body = [];
  if (has_clause) {
    Type handler = %(($_handler_type));
    body.push(%(stmnt (expr (void)
      (call "x2c_error_catch_close"
        (args (expr $handler (ident $handle)))))));
    body.push(%(stmnt (expr $handler
      (op = (expr $handler (ident $handle)) (expr $handler (nil))))));
  }
  if (finalizer) body.push(finalizer);
  List statements = body.list_free();
  if (finalizer)
    statements = %((if (expr (int)
      (call "x2c_exception_claim" (args ${_address_of(_frame_type, frame)})))
      (block @statements)));
  return statements.append(
    %(${_region_call("x2c_exception_leave", _frame_type, frame)}));
}

/* The statements that leave every region down to `stop`, innermost first.
   Each region runs its own statements before the next one out, so an inner
   frame leaves before an outer defer runs. */
static List _unwind(Walk walk, int stop) {
  Array statements = [];
  for (int i = (int) walk.regions.len() - 1; i >= stop; i--)
    foreach (List statement, walk.regions[i].list().car().list())
      statements.push(statement);
  return statements.list_free();
}

/* Wrap a transfer in the cleanup it runs first. A transfer that leaves no
   region keeps its own shape. */
static List _transfer(Walk walk, int stop, List statement) {
  List cleanup = _unwind(walk, stop);
  return cleanup ? %(block @cleanup $statement) : statement;
}

/* The open regions, innermost first. A label's ancestry is this list, and a
   jump may only leave a suffix of it. */
static List _region_path(Walk walk) {
  List path = %();
  foreach (List region, walk.regions) path = cons(region.cadr(), path);
  return path;
}

/* A label reads as a binding, as a wrapped expression, or as the bare name
   a macro wrote. */
static String _label_spelling(Var label) {
  if (label is <string>) return label;
  if (label is not <list>) return NULL;
  List node = label;
  match (node) {
    case %(ident ?binding): return binding_identity_spelling(binding);
    case %(!or (expr ? ?inner) (parens ?inner)): return _label_spelling(inner);
    case %(?(String name)): return name;
  }
  return binding_identity_spelling(node);
}

/* Collect each label's region ancestry before any `goto` is rewritten, so a
   jump backward to a label reads the same ancestry as a jump forward. The
   ancestry is the chain of region nodes enclosing the label, and the rewrite
   compares against the same nodes. */
static void _collect_labels(Walk walk, Var value, List path) {
  if (value is not <list> || value.is_nil()) return;
  List node = value;
  match (node) {
    // A label is a statement, and an expression nests as deeply as it is
    // long, so the walk stops here.
    case %(expr *): return;
    case %(label ?name *rest): {
      String spelling = _label_spelling(name);
      if (spelling) walk.labels[spelling] = path;
      foreach (Var child, rest) _collect_labels(walk, child, path);
      return;
    }
    /* Each region a construct opens has its own identity: a `try` protects
       its body and each catch arm separately, while its guards and its
       finalizer run outside the region and keep the enclosing path. */
    case %(try ?body ?clause ?finalizer *): {
      _collect_labels(walk, body, cons(body, path));
      match (clause)
        case %(catcharms ?records):
          foreach (List record, records) {
            _collect_labels(walk, record.car(), path);
            _collect_labels(walk, record.cadr(), path);
            List arm = record.caddr();
            _collect_labels(walk, arm, cons(arm, path));
          }
      _collect_labels(walk, finalizer, path);
      return;
    }
    case %(defer ?body *): {
      _collect_labels(walk, body, cons(body, path));
      return;
    }
    case %(localinit ?guard ?body): {
      _collect_labels(walk, guard, path);
      _collect_labels(walk, body, cons(node, path));
      return;
    }
  }
  foreach (Var child, node) _collect_labels(walk, child, path);
}

/* Report at `origin`, and leave the compiler's origin as it was for whatever
   reports next. */
static void _report_at(Walk w, int origin, String message, List note) {
  $let(w.compiler.origin, origin)
    w.compiler.report_error(<emit>, message, NULL, note);
}

/* Reject a jump that would enter a region it did not open, and return the
   depth the jump unwinds to. */
static int _goto_stop(Walk walk, Var label) {
  String name = _label_spelling(label);
  Var stored;
  if (!name || !walk.labels.try_get(name, &stored)) {
    _report_at(walk, walk.origin,
               "goto target label is not defined in this function", NULL);
    return (int) walk.regions.len();
  }
  List target = stored, source = _region_path(walk);
  int source_depth = source.len(), target_depth = target.len();
  List suffix = source;
  for (int i = source_depth; i > target_depth && suffix; i--)
    suffix = suffix.cdr();
  if (target_depth > source_depth || suffix !== target) {
    _report_at(walk, walk.origin,
               "goto cannot enter or cross a protected cleanup region",
               %("jump only within the same region or outward"));
    return (int) walk.regions.len();
  }
  return target_depth;
}

/* C requires automatic state changed after `sigsetjmp` to be volatile once
   `siglongjmp` returns. These are the forms that change their left operand;
   the operand names the object directly, or names a pointer that holds it. */
static Var _changed_operand(List node) {
  match (node) {
    case %(op ?operator ?target *): {
      if (operator is <symbol> && ast_changes_left_operand(operator))
        return target;
      return NULL;
    }
    case %((!or vcompound vpostfix) ?target *): return target;
    case %(postfix ? ?target): return target;
  }
  return NULL;
}

static int _automatic_static_input(Compiler c, List binding) {
  Var automatic, stored;
  Map facts = c.semantic_binding_facts();
  if (!facts.try_get(%(automatic $binding), &automatic) ||
      !automatic.truth()) return 0;
  if (!facts.try_get(%(type $binding), &stored)) return 1;
  Type type = stored;
  return !type.is_static() && !type.is_extern() && !type.is_threaded();
}

/** Reports whether the static local initializer `value` has to run at
    runtime, because it reads an automatic object or another static this
    function initializes. `runtime` holds the statics already known to run
    that way, and gains this one's bindings.
*/
int Compiler.static_value_is_runtime(Compiler c, List value, Map runtime) {
  Array pending = [], modes = [];
  defer pending.free();
  defer modes.free();
  pending.push(value);
  modes.push(0);
  while (pending.len()) {
    List node = pending.take_last();
    int address = modes.take_last();
    if (address) {
      match (node) {
        case %(!or (expr ? ?inner) (parens ?inner)
                   (op . ?inner ?)): {
          pending.push(inner);
          modes.push(1);
          continue;
        }
        case %(ident ?binding): {
          if (binding in runtime ||
              _automatic_static_input(c, binding)) return 1;
          continue;
        }
        case %(index (!set ?base (expr ?type ?)) ?index): {
          pending.push(index);
          modes.push(0);
          pending.push(base);
          modes.push(type.list().type().is_array());
          continue;
        }
        case %(op (!quote *) ?inner): {
          pending.push(inner);
          modes.push(0);
          continue;
        }
      }
      return 1;
    }
    match (node) {
      case %((!or cache call var array map initval) *): return 1;
      case %(expr ?type (ident ?binding)): {
        if (binding in runtime ||
            _automatic_static_input(c, binding)) return 1;
        Type native = type;
        if (native && !native.is_enum() && !native.is_function() &&
            !native.is_array() &&
            (native.is_pointer() || !native.contains(<const>))) return 1;
        continue;
      }
      case %(expr ? (op & ?inner)): {
        pending.push(inner);
        modes.push(1);
        continue;
      }
      case %(expr ?type (!set ?content (index *))): {
        Type native = type;
        if (native.is_array()) {
          pending.push(content);
          modes.push(1);
          continue;
        }
        if (native.is_pointer() || !native.contains(<const>)) return 1;
      }
      case %(expr ? (sizeof ?)): continue;
    }
    foreach (Var child, node)
      if (child is <list>) {
        pending.push(child);
        modes.push(0);
      }
  }
  return 0;
}

static int _runtime_static_declaration(
  Compiler c, List node, Map runtime) {
  int found = 0;
  match (node) {
    case %(at ? ?body): return _runtime_static_declaration(c, body, runtime);
    case %(declare (!set ?type (*)) (bindings *bindings)):
      if (type.list().type().is_static())
        foreach (List binding, bindings)
          match (binding)
            case %(op = (bind ?name ?) ?value):
              if (c.static_value_is_runtime(value, runtime)) {
                runtime[name] = 1;
                found = 1;
              }
  }
  return found;
}

/* A static local whose initializer runs at runtime protects the remainder
   of its block just as a cleanup region does: a jump may not enter past the
   initializer. Keeping the canonical binding makes shadowing and generated
   syntax use the same object reference. */
static List _static_regions(Compiler c, List ast, Map runtime) {
  match (ast) {
    case %((!or function localinit expr declare typedef) *): return ast;
    case %(block *statements): {
      Array before = [];
      foreach (List statement, statements) {
        if (_runtime_static_declaration(c, statement, runtime)) {
          List rest = statements;
          for (int i = 0; i <= before.len(); i++) rest = rest.cdr();
          List body = _static_regions(c, %(block @rest), runtime);
          before.push(%(localinit $statement $body));
          return %(block @{before.list_free()});
        }
        before.push(_static_regions(c, statement, runtime));
      }
      return %(block @{before.list_free()});
    }
  }
  Var child;
  $ast.rewrite_children(ast, child, _static_regions(c, child, runtime));
}

/* Names whose storage a transfer may leave stale: those a `try` body writes,
   and those a `defer` inside one writes through its environment. The flag
   covers a subtree, so a write outside every `try` preserves nothing.
   `holders` gains the pointers the body writes through, whose own locals
   `_collect_aliased` resolves. */
static void _collect_preserved(
  Var value, int in_try, Map names, Map holders) {
  /* A long expression chain nests as deeply as it is long, so the walk keeps
     its pending work off the C stack. */
  Array pending = $auto([value]), flags = $auto([in_try]);
  while (pending.len()) {
    Var current = pending.take_last();
    int inside = flags.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    if (inside) {
      Var operand = _changed_operand(node);
      String name = ast_direct_identifier(operand);
      if (name) names[name] = 1;
      String holder = ast_indirect_identifier(operand);
      if (holder) holders[holder] = 1;
    }
    match (node) {
      case %(function *): continue;
      case %(defer ?body ? ? ? ?written *): {
        if (inside)
          foreach (List binding, written) {
            String captured = binding_identity_spelling(binding);
            if (captured) names[captured] = 1;
          }
        pending.push(body);
        flags.push(inside);
        continue;
      }
      case %(try ?body ?clause ?finalizer *): {
        foreach (Var part, %($body $clause $finalizer)) {
          pending.push(part);
          flags.push(1);
        }
        continue;
      }
    }
    foreach (Var child, node) {
      pending.push(child);
      flags.push(inside);
    }
  }
}

/* Preserve the locals whose address one of `holders` took. A write through
   such a pointer changes the local without naming it, so the local needs the
   qualifier the write itself does not ask for. */
static void _collect_aliased(Var value, Map holders, Map names) {
  Array pending = $auto([value]);
  while (pending.len()) {
    Var current = pending.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    match (node) case %(op = ?target ?source): {
      String addressed = ast_addressed_identifier(source), holder = NULL;
      match (target) case %(bind ?binding ?):
        holder = binding_identity_spelling(binding);
      if (!holder) holder = ast_direct_identifier(target);
      if (addressed && holder && holder in holders) names[addressed] = 1;
    }
    foreach (Var child, node) pending.push(child);
  }
}

static Var _rewrite(Walk walk, Var value);
static List _function(Compiler compiler, List node);

/* Rewrite a construct's body with the transfer barriers it establishes. A
   loop bounds both `break` and `continue`; a switch bounds only `break`,
   because a `continue` inside it still targets the enclosing loop. */
static Var _bounded(Walk walk, Var body, int is_loop) {
  int saved_break = walk.break_stop, saved_continue = walk.continue_stop;
  walk.break_stop = (int) walk.regions.len();
  if (is_loop) walk.continue_stop = (int) walk.regions.len();
  Var result = _rewrite(walk, body);
  walk.break_stop = saved_break;
  walk.continue_stop = saved_continue;
  return result;
}

/* Rewrite a region's body and its handlers with the region open. */
static Var _inside(Walk walk, List cleanup, List marker, Var body) {
  walk.regions.push(%($cleanup $marker));
  Var result = _rewrite(walk, body);
  walk.regions.take_last();
  return result;
}

/* Qualify one binding that a transfer may leave stale. */
static List _preserve_binding(List bind, Map names) {
  match (bind)
    case %(bind ?name ?mods): {
      String spelling = binding_identity_spelling(name);
      if (spelling && spelling in names && !mods.contains(<volatile>))
        return %(bind $name ${cons(<volatile>, mods)});
    }
  return bind;
}

static int _declares_preserved(List bindings, Map names) {
  foreach (List binding, bindings.cdr())
    match (binding)
      case %(!or (bind ?name ?) (op = (bind ?name ?) ?)): {
        String spelling = binding_identity_spelling(name);
        if (spelling && spelling in names) return 1;
      }
  return 0;
}

/* Static, extern, threaded, and typedef declarations do not have automatic
   storage, so a transfer cannot leave them stale. */
static int _is_automatic(List declaration) {
  Type type = declaration.cadr();
  return !type.is_static() && !type.is_extern() && !type.is_typedef() &&
         !type.is_threaded();
}

/* A pointer initialized with the address of a preserved local points at a
   volatile object, so its pointee type must say so or C rejects dropping
   the qualifier. */
static List _preserve_pointee(List type, List bindings, Map names) {
  match (bindings)
    case %(bindings (op = (bind ? ((!quote *))) ?value)): {
      String name = ast_addressed_identifier(value);
      if (name && name in names &&
          !type.type().flatten_all().contains(<volatile>))
        return cons(<volatile>, type);
    }
  return type;
}

/* Qualify the declarations and parameters the set names. C puts a qualifier
   on the whole declaration, so a statement declaring several names splits
   into one declaration each. */
static Var _preserve(Var value, Map names) {
  if (value is not <list> || value.is_nil()) return value;
  List node = value;
  // Only declarations and parameters carry a qualifier, and neither appears
  // inside an expression.
  match (node) case %(expr *): return value;
  match (node) {
    case %(param ?type ?bind):
      return %(param $type ${_preserve_binding(bind, names)});
    case %(block *statements): {
      Array output = [];
      foreach (Var statement, statements) {
        Var lowered = _preserve(statement, names);
        List origin = NULL, Var inner = lowered;
        match (inner) case %(at ?anchor ?wrapped): {
          origin = anchor;
          inner = wrapped;
        }
        match (inner)
          case %(!set ?declaration
                 ((!or declare decl) ?type
                  (!set ?bindings (bindings ? ? *)))):
            if (_is_automatic(declaration) &&
                _declares_preserved(bindings, names)) {
              Symbol head = declaration.car();
              foreach (List binding, bindings.cdr()) {
                List one = %($head $type (bindings $binding));
                output.push(origin ? %(at $origin $one) : one);
              }
              continue;
            }
        output.push(lowered);
      }
      return %(block @{output.list_free()});
    }
    case %(!set ?declaration
           ((!or declare decl) ?type (!set ?bindings (bindings *)))): {
      Symbol head = declaration.car();
      if (!_is_automatic(declaration)) return node;
      type = _preserve_pointee(type, bindings, names);
      Array preserved = [];
      foreach (List binding, bindings.cdr())
        match (binding) {
          case %(op = ?bind ?value):
            preserved.push(
              %(op = ${_preserve_binding(bind, names)} $value));
          case %(bind * ): preserved.push(_preserve_binding(binding, names));
        }
      return %($head $type (bindings @{preserved.list_free()}));
    }
  }
  Var child;
  $ast.rewrite_children(node, child, _preserve(child, names));
}

/* Save the returned value before cleanup runs, since cleanup may change the
   state the expression read. */
static List _return_value(Walk walk, List expression) {
  List binding = _region_binding(walk.compiler, "return_value");
  Type type = walk.return_type;
  /* The declarator carries the type's pointer and array modifiers, so the
     saved value declares the way the function's result is spelled. */
  List (base, mods) = type.declaration_parts();
  List declaration = %(declare $base
    (bindings (op = (bind $binding $mods) $expression)));
  List statement = _transfer(walk, 0, %(return (expr $type (ident $binding))));
  return %(block $declaration $statement);
}

static Var _rewrite(Walk walk, Var value) {
  if (value is not <list> || value.is_nil()) return value;
  List node = value;
  // An expression holds no transfer and no region, and nests as deeply as it
  // is long, so the walk stops here.
  match (node) case %(expr *): return value;
  match (node) {
    case %(defer ?body ?env ?callback ?records ?): {
      walk.compiler.needs_exception = 1;
      List record = _region_binding(walk.compiler, "defer_record");
      List cleanup = _defer_cleanup(record);
      return %(defer ${_inside(walk, cleanup, body, body)} $env $callback
               $records $record $cleanup);
    }
    case %(try ?body ?clause ?finalizer): {
      walk.compiler.needs_exception = 1;
      List frame = _region_binding(walk.compiler, "exception_frame");
      List handle = clause
        ? _region_binding(walk.compiler, "error_handler") : NULL;
      int labelled_at = walk.origin;
      Var labelled = _finalizer_label(finalizer, walk.origin, &labelled_at);
      if (labelled) {
        String name = _label_spelling(labelled);
        _report_at(
          walk, labelled_at, "a finally body cannot define a label",
          %("a finalizer runs on every path that leaves its region, so '${
            name ? name : "this label"}' would be defined once for each"));
      }
      List cleanup = _try_cleanup(
        frame, handle, _rewrite(walk, finalizer), !!clause);
      List body_out = _inside(walk, cleanup, body, body);
      /* A catch arm runs inside the region it handles, so it leaves the
         same statements behind on its own exits. Each arm is its own
         region, which a jump from the body may not enter. */
      List clause_out = clause;
      match (clause)
        case %(catcharms ?records): {
          Array rewritten = [];
          foreach (List record, records) {
            List arm = record.caddr();
            rewritten.push(%(${record.car()} ${record.cadr()}
                             ${_inside(walk, cleanup, arm, arm)}));
          }
          clause_out = %(catcharms ${rewritten.list_free()});
        }
      return %(try $body_out $clause_out $frame $handle $cleanup);
    }
    /* A function-static initializer leaves its own record at the end of its
       block. No exit runs that record, but a jump still may not enter the
       region, so it takes part in the ancestry a label is compared by. */
    case %(localinit ?guard ?body):
      return %(localinit ${_rewrite(walk, guard)}
               ${_inside(walk, NULL, node, body)});
    case %(at ?(int origin) ?inner): {
      int previous = walk.origin;
      walk.origin = origin;
      Var lowered = _rewrite(walk, inner);
      walk.origin = previous;
      return %(at $origin $lowered);
    }
    case %(return): return _transfer(walk, 0, node);
    case %(return (!set ?expression (expr ? ?))): {
      /* Only a region that runs something can change what the expression
         read, so a static-local region alone leaves the return as it is. */
      if (!_unwind(walk, 0)) return node;
      return _return_value(walk, expression);
    }
    case %(break): return _transfer(walk, walk.break_stop, node);
    case %(continue): return _transfer(walk, walk.continue_stop, node);
    case %(goto ?label): return _transfer(walk, _goto_stop(walk, label), node);
    case %(while ?condition ?body):
      return %(while ${_rewrite(walk, condition)} ${_bounded(walk, body, 1)});
    case %(do ?body ?condition):
      return %(do ${_bounded(walk, body, 1)} ${_rewrite(walk, condition)});
    case %(for ?initial ?condition ?increment ?body):
      return %(for ${_rewrite(walk, initial)} ${_rewrite(walk, condition)}
               ${_rewrite(walk, increment)} ${_bounded(walk, body, 1)});
    case %(switch ?expression ?body):
      return %(switch ${_rewrite(walk, expression)}
               ${_bounded(walk, body, 0)});
    /* A `match` emits a switch over its arms, so an arm's `break` leaves the
       match and no region with it. Its `continue` still reaches the
       enclosing loop. */
    case %(matchcases ?subject ?records):
      return %(matchcases ${_rewrite(walk, subject)}
               ${_bounded(walk, records, 0)});
    case %(function *): return _function(walk.compiler, node);
  }
  Var child;
  $ast.rewrite_children(node, child, _rewrite(walk, child));
}

/* Each function walks on its own: no loop, switch, or region spans a
   function boundary, including a lambda body lifted into a sibling. */
static List _function(Compiler compiler, List node) {
  match (node)
    case %(function ?type ?bindings ?body): {
      List declaration = %(declare $type (bindings $bindings));
      struct Walk state = {
        compiler, [], 0, 0, 0, {},
        cdr(declaration.type_from_ast()).type().declared()
      };
      Walk walk = &state;
      Map runtime = {};
      body = _static_regions(compiler, body, runtime);
      _collect_labels(walk, body, NULL);
      Map preserved = {}, holders = {};
      _collect_preserved(body, 0, preserved, holders);
      if (holders.len()) _collect_aliased(body, holders, preserved);
      List rewritten = _rewrite(walk, body);
      if (preserved.len()) {
        rewritten = _preserve(rewritten, preserved);
        bindings = _preserve(bindings, preserved);
      }
      state.regions.free();
      return %(function $type $bindings $rewritten);
    }
  return node;
}

static Var _units(Compiler compiler, Var value) {
  if (value is not <list> || value.is_nil()) return value;
  List node = value;
  match (node) {
    case %(function *): return _function(compiler, node);
    // Lambdas are lifted into siblings before this pass, so no function
    // definition hides inside an expression for the walk to find.
    case %(expr *): return value;
  }
  Var child;
  $ast.rewrite_children(node, child, _units(compiler, child));
}

/** Names each cleanup region, records the statements that leave it, and
    runs them on every exit that leaves it. `ast` must be a transformed
    top-level unit whose `defer` and `try` forms are final; the pass rewrites
    transfers, so it runs once, after the transform driver reaches its fixed
    point.
*/
List Compiler.mark_cleanup_regions(Compiler c, List ast) => _units(c, ast);
