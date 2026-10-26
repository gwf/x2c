/*  production.x -- declaration production

   A declaration producer's source effects wait until production needs
   their state. Collection retains the bundle a producer returns with its
   token span, and the full parse replays that bundle. */

static List _declaration_source_key(Compiler c, Token token) {
  String path = Compiler.portable_path(c.canonical_path(c.filename));
  return %("source-node" (declaration $path $(token.pos)));
}

/** Expands the file-scope unit macro at the cursor for collection and
    reports whether it did. A required expansion reports its errors. A tried
    expansion that fails keeps nothing and leaves the cursor at the
    invocation, so collection skips it and the full parse reports it.
*/
int Compiler.collect_unit_macro(Compiler c) {
  Symbol collection = c.macro_invocation_collection();
  if (collection == <tried> || (collection && c.meta_build))
    return _try_unit_macro(c);
  if (collection == <required>) _expand_unit_macro(c);
  return collection == <required>;
}

static int _try_unit_macro(Compiler c) {
  Token first = c.token;
  int failed = 0;
  SymTxn transaction = c.begin_semantic_transaction();
  DiagnosticsHold hold = c.diagnostics.hold();
  with (c.recovery_depth = c.recovery_depth + 1) {
    try _expand_unit_macro(c);
    catch %(malformed *): failed = 1;
  }
  c.diagnostics.release(hold, 0);
  if (!failed) transaction.commit();
  else {
    transaction.rollback();
    c.token = first;
  }
  return !failed;
}

/* The expansion retains its declarations for collection, and its private
   helpers remain available to later invocations. Generated-name counters
   are restored when the full parse must expand it again. */
static void _expand_unit_macro(Compiler c) {
  Map counters = c.names.counters;
  c.names.counters = counters.copy();
  Token first = c.token;
  List syntax = c.parse_top_level();
  int retained = _retain_bundle(c, syntax, first, c.token);
  /* The full parse expands this unit again. Keep the declarations needed
     by later shallow invocations, but do not count its generated names
     twice. */
  if (!retained) c.names.counters = counters;
}

/* The owning source records one declaration production and its token span.
   Both parses share its Context, bindings, origins, and macro frames.
   Full parsing consumes the result without invoking its producer again. */
static int _retain_bundle(
  Compiler c, List syntax, Token first, Token after) {
  match (syntax) {
    case %(seq ?only): return _retain_bundle(c, only, first, after);
    case %(declaration-bundle (rows *)): {
      c.sym.set(
        _declaration_source_key(c, first),
        %(declaration-source $(after.pos) $syntax
          $(c.semantic_binding_facts())));
      return 1;
    }
  }
  return 0;
}

/** Binds a retained declaration production at the cursor, then advances
    past its source. Returns NULL when collection retained no production.
*/
List Compiler.replay_declaration_source(Compiler c) {
  List source = c.sym.get(_declaration_source_key(c, c.token));
  match (source)
    case %(declaration-source ?(int end) ?syntax ?facts): {
      List bound;
      with (c.replaying_declaration = 1) {
        _restore_declaration_bindings(c, syntax, facts, {});
        bound = c.bind_syntax(syntax, <unit>, NULL);
      }
      while (c.peek(0) != <eof> && c.token.pos < end) c.next();
      return bound;
    }
  return NULL;
}

/* Register only this production's identities. Shared macro frames are
   visited once, and later source declarations keep their ordinary order. */
module void _restore_declaration_bindings(
  Compiler c, Var syntax, Map facts, Map seen) {
  if (syntax is not <list> || syntax in seen) return;
  seen[syntax] = 1;
  int identity = 0;
  String spelling = NULL;
  if (Ast.try_binding(syntax, identity, spelling)) {
    c.set_fact(%(known $identity), spelling);
    c.set_fact(
      %(source-spelling $syntax),
      facts.getdefault(%(source-spelling $syntax), spelling));
    return;
  }
  foreach (Var child in syntax.list())
    _restore_declaration_bindings(c, child, facts, seen);
}
