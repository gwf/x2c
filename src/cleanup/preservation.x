/*  preservation.x -- automatic storage across exception landings */

/* Whether a statement expression in `body`, before its regions lower,
   holds a landing form. Only a landing's rows hold source the walk
   lowers, so only they are searched. */
module int _expression_holds_landing(List body) {
  List node;
  $ast.walk(body, node) match (node) {
    case %(expr *): {
      if (Ast.contains_head(node, <landing>)) return 1;
      continue;
    }
    case %(landing ? ?rows): {
      foreach (List row in rows)
        match (row) case %((!or outer region) ? ?part):
          if (_expression_holds_landing(part)) return 1;
      continue;
    }
  }
  return 0;
}

// volatile locals

/* Names whose storage a transfer may leave stale: those the parts of a
   landing form write, such as a `try` body, and those a `defer` inside one
   writes through its environment. The flag covers a subtree, so a write
   outside every landing preserves nothing. A long expression chain nests
   as deeply as it is long, so the walk keeps its pending work off the C
   stack. */
module void _collect_writes(Preserve &p, List body) {
  auto Array pending = [body], flags = [0];
  while (pending.len()) {
    Var current = pending.take_last();
    int inside = flags.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    if (inside) _write(p, node);
    match (node) {
      case %(function *): continue;
      case %(defer ?body ? ? ? ?written *): {
        if (inside)
          foreach (List binding in written) {
            String captured = Ast.binding_spelling(binding);
            if (captured) p.names[captured] = 1;
          }
        pending.push(body);
        flags.push(inside);
        continue;
      }
      case %(landing ? ?rows): {
        foreach (List row in rows)
          match (row) case %((!or outer region) ? ?part): {
            pending.push(part);
            flags.push(1);
          }
        continue;
      }
    }
    foreach (Var child in node) {
      pending.push(child);
      flags.push(inside);
    }
  }
  if (p.holders.len()) _aliased(p, body);
}

/* `holders` gains the pointers the body writes through, whose own locals
   `_aliased` resolves. `escaped` gains the locals whose address the body
   hands to a callee. A callee's pointer parameter has no `volatile`, so
   qualifying the local would discard the qualifier at the call. Its
   address escapes at its declaration instead, which keeps its value in
   memory across a transfer. */
static void _write(Preserve &p, List node) {
  Var operand = _changed_operand(p.c, node);
  if (!operand) {
    match (node) case %(call ? (args *arguments)):
      foreach (Var argument in arguments) {
        String addressed = Ast.addressed_identifier(argument);
        if (addressed) p.escaped[addressed] = 1;
      }
    return;
  }
  String name = Ast.direct_identifier(operand);
  if (name) p.names[name] = 1;
  String holder = Ast.indirect_identifier(operand);
  if (holder) p.holders[holder] = 1;
}

/* C requires automatic state changed after `sigsetjmp` to be volatile once
   `siglongjmp` returns. These are the source writes and the lowered update
   helpers; the operand names the object directly, or names a pointer that
   holds it. */
static Var _changed_operand(Compiler c, List node) {
  List written = Ast.written_operand(node);
  if (written) return written;
  match (node) {
    case %(call ?(String helper)
                (args (expr ? (op & (parens ?target))) *)): {
      if (helper == "x2c_var_update_volatile"
          || helper == "x2c_var_postfix_volatile"
          || helper == "Var_update" || helper == "Var_postfix") return target;
      Type native = c.sym.resolve_numeric_type(target.list().cadr());
      if (native && helper == native.var_numeric_update_helper())
        return target;
      foreach (Var (key, value) in c.protocol_helpers)
        match (key)
          case %("protocol-update-helper" *):
            if (value == helper) return target;
    }
  }
  return NULL;
}

/* Preserve the locals whose address one of `holders` took. A write through
   such a pointer changes the local without naming it, so the local needs the
   qualifier the write itself does not ask for. `pointers` gains the holders
   that resolved, because their pointee type has to carry the qualifier too. */
static void _aliased(Preserve &p, List body) {
  List node;
  $ast.walk(body, node) match (node) case %(op = ?target ?source): {
    String addressed = Ast.addressed_identifier(source), holder = NULL;
    match (target) case %(bind ?binding ?):
      holder = Ast.binding_spelling(binding);
    if (!holder) holder = Ast.direct_identifier(target);
    if (addressed && holder && holder in p.holders) {
      p.names[addressed] = 1;
      p.pointers[holder] = 1;
    }
  }
}

module Var _preserve_locals(Preserve &p, Var value) {
  if (value is not <list> || value.is_nil()) return value;
  List node = value;
  // Only declarations and parameters carry a qualifier. A statement
  // expression's own locals follow any landing around it, so they need one
  // only when a statement expression in the function holds a landing.
  match (node) case %(expr *):
    return p.expression_landings
      ? _rewrite_expression(
        node, %!(List block) using &p => _preserve_locals(p, block))
      : node;
  match (node) {
    case %(param ?type ?bind):
      return %(param $type ${_binding(p, bind, p.escaped)});
    case $source_block_content(%(*statements)): return _block(p, statements);
    case %(!set ?declaration ((!or declare decl) ? (bindings *))):
      return _declaration(p, declaration, NULL);
  }
  Var child;
  $ast.rewrite_children(node, child, _preserve_locals(p, child));
}

/* Qualify the declarations and parameters the sets name. C puts a qualifier
   on the whole declaration - on the declarator for the object itself, and on
   the base type for a pointee - so a statement that qualifies any of several
   names splits into one declaration each. A local in `escaped` escapes
   right after its declaration; one declared anywhere else is qualified. */
static List _block(Preserve &p, List statements) {
  Array output = [];
  foreach (List statement in statements) {
    int origin = 0, Var inner = statement;
    match (inner) case %(at ?(int anchor) ?wrapped): {
      origin = anchor;
      inner = wrapped;
    }
    match (inner)
      case %(!set ?declaration
             ((!or declare decl) ?type (!set ?bindings (bindings *)))):
        if (_is_automatic(declaration)) {
          _split(p, output, origin, declaration, type, bindings);
          continue;
        }
    List loop = _escape_loop(p, inner);
    if (loop) {
      output.push(origin ? %(at $origin $loop) : loop);
      continue;
    }
    output.push(_preserve_locals(p, statement));
  }
  return source_block_content(output.list_free());
}

/* Split before qualifying, so a base-type qualifier one declarator needs
   does not reach the names beside it. */
static void _split(
  Preserve &p, Array output, int origin, List declaration, Type type,
  List bindings) {
  List parts = %($declaration);
  if (_declares_name(p, bindings) || _declares_pointee(p, bindings)) {
    Symbol head = declaration.car();
    Array split = [];
    foreach (List binding in bindings.cdr())
      split.push(%($head $type (bindings $binding)));
    parts = split.list_free();
  }
  foreach (List part in parts) {
    List one = _declaration(p, part, p.escaped);
    output.push(origin ? %(at $origin $one) : one);
  }
  _escape_declared(p, output, bindings.cdr());
}

/* `escaped` is the set whose locals escape rather than take the qualifier,
   or NULL where no escape can follow the declaration. */
static List _declaration(Preserve &p, List declaration, Map escaped) {
  if (!_is_automatic(declaration)) return declaration;
  Symbol head = declaration.car();
  Type type = declaration.cadr();
  List bindings = declaration.caddr();
  if (_declares_pointee(p, bindings) &&
      !(<volatile> in type.type().flatten_all()))
    type = cons(<volatile>, type);
  Array preserved = [];
  foreach (List binding in bindings.cdr())
    match (binding) {
      case %(op = ?bind ?value):
        preserved.push(
          %(op = ${_binding(p, bind, escaped)} ${_preserve_locals(p, value)}));
      case %(bind * ): preserved.push(_binding(p, binding, escaped));
    }
  return %($head $type (bindings @{preserved.list_free()}));
}

/* Qualify one binding that a transfer may leave stale, unless `escaped`
   names it: its address escapes instead. */
static List _binding(Preserve &p, List bind, Map escaped) {
  match (bind)
    case %(bind ?name ?mods): {
      String spelling = Ast.binding_spelling(name);
      if (spelling && spelling in p.names &&
          !(escaped && spelling in escaped) && !(<volatile> in mods))
        return %(bind $name ${cons(<volatile>, mods)});
    }
  return bind;
}

static int _declares_name(Preserve &p, List bindings) {
  foreach (List binding in bindings.cdr())
    match (binding)
      case $source_declarator_row(%(?name ?)): {
        String spelling = Ast.binding_spelling(name);
        if (spelling && spelling in p.names) return 1;
      }
  return 0;
}

/* A pointer that holds the address of a preserved local points at a volatile
   object, so its pointee type must say so or C rejects dropping the
   qualifier. `pointers` names the holders the walk resolved, which covers a
   pointer assigned after its declaration; an initializer that takes the
   address directly says the same thing on its own. */
static int _declares_pointee(Preserve &p, List bindings) {
  foreach (List binding in bindings.cdr()) {
    List declarator = binding;
    match (binding) case %(op = ?bind ?value): {
      String addressed = Ast.addressed_identifier(value);
      if (addressed && addressed in p.names) return 1;
      declarator = bind;
    }
    match (declarator) case %(bind ?name ?): {
      String spelling = Ast.binding_spelling(name);
      if (spelling && spelling in p.pointers) return 1;
    }
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

/* A `for` that declares a local in `escaped` moves the declaration into a
   block around the loop, so the address escapes once, before the loop. */
static List _escape_loop(Preserve &p, List loop) {
  match (loop)
    case %(for (decl ?type (!set ?bindings (bindings *binds))) *rest): {
      Array output = [];
      _escape_declared(p, output, binds);
      List escapes = output.list_free();
      if (!escapes) return NULL;
      List declaration = _declaration(
        p, %(declare $type $bindings), p.escaped);
      List remaining = _preserve_locals(p, %(for () @rest));
      return source_block_content(%($declaration @escapes $remaining));
    }
  return NULL;
}

/* Escape the address of each of `binds` that `escaped` names. Once the
   runtime holds a local's address, C must assume every later call,
   `sigsetjmp` and the raise included, reads and writes the local. */
static void _escape_declared(Preserve &p, Array output, List binds) {
  Compiler c = p.c;
  foreach (List bind in binds)
    match (bind)
      case $source_declarator_row(%(?name ?)): {
        String spelling = Ast.binding_spelling(name);
        if (spelling && spelling in p.escaped) {
          output.push(
            c.bind_syntax(
              $!{ x2c_exception_escaped = &$name; }, <block>,
              c.return_type));
        }
      }
}

/* A parameter in `escaped` escapes before the function body runs. */
module List _escape_parameters(Preserve &p, List body, List bindings) {
  Array output = [];
  match (bindings) case %(bind ? ((fnmod (params *parameters)) *)):
    foreach (List parameter in parameters)
      match (parameter) case %(param ? ?bind):
        _escape_declared(p, output, %($bind));
  return p.c.prepend_setup(body, output.list_free());
}
