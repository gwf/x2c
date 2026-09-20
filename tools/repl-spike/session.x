/*  session.x -- persistent compiler submissions for the REPL research spike

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "frontend.x"

/** The caller keeps the compiler's unit Context open until every result and
    this session are finished. Results borrow that Context's storage. */
typedef struct ReplSession {
  Compiler compiler;
  Map names;
} *ReplSession;

/** status is incomplete, rejected, defined, executed, value, or failed.
    diagnostics are ordinary compiler reports; message/cause describe the
    adapter or evaluator failure. syntax and lowered support optional tracing. */
typedef struct ReplResult {
  Symbol status;
  Var value;
  String name, message;
  List diagnostics, cause, syntax, lowered;
} ReplResult;

#pragma private
#include "comptime.x"
#include "parse.x"
#include "diagnostics.x"
#include "lisp.x"

ReplSession ReplSession.new(Compiler compiler) {
  ReplSession session = Scope.calloc(1, sizeof(struct ReplSession));
  session.compiler = compiler;
  session.names = {};
  return session;
}

static List _bare(List node) {
  match (node) case %(at ? ?inner): return inner;
  return node;
}

static List _thunk(List items) =>
  %(function (int)
    (bind (binding -1 "__repl_eval") ((fnmod (params))))
    (block @items));

static void _refuse(String why) { raise %(spike (why $why)); }

// Native C can resolve an untyped name later; this evaluator cannot.
static void _require_bound(Var syntax) {
  match (syntax)
    case %(expr () (ident (binding ? ?name))):
      _refuse(%"unresolved identifier: $name");
  if (syntax is <list>) foreach (Var child, syntax.list())
    _require_bound(child);
}

static List _initializers(List node, Map names, Array added, Array ids) {
  Array statements = [];
  defer statements.free();
  match (node) {
    case %(declare ?spec (bindings *bindings)): {
      foreach (List item, bindings) {
        match (item) {
          case %(op = (bind (binding ?id ?(String name)) ()) ?value): {
            if (names.contains(name) || added.contains(name) ||
                name.startswith("__repl_"))
              _refuse("redeclaration is disabled; use assignment");
            added.push(name);
            ids.push(id);
            statements.push(%(stmnt
              (expr $spec (op = (expr $spec (ident (binding $id $name)))
                               $value))));
            continue;
          }
        }
        _refuse("top-level values need an initializer and a simple binding");
      }
      return _thunk(statements);
    }
  }
  _refuse("this top-level form is outside the spike");
  return NULL;
}

static List _result_body(List fn, int *prints) {
  match (fn) {
    case %(function ? ? (block *body)): {
      Array items = body;
      defer items.free();
      if (items.len()) {
        List last = _bare(items[items.len() - 1]);
        match (last) {
          case %(stmnt (expr ?spec ?value)): {
            int effect = 0;
            match (value) {
              case %(op ?operator *):
                effect = %("=" "++" "--" "+=" "-=" "*=" "/=" "%="
                           "&=" "|=" "^=" "<<=" ">>=").contains(operator.str());
              case %(postfix *): effect = 1;
            }
            if (!effect) {
              items[items.len() - 1] = %(return $spec (expr $spec $value));
              *prints = 1;
            }
          }
        }
      }
      return _thunk(items);
    }
  }
  return fn;
}

/** Submits one complete candidate without printing or retaining a pending
    prefix. Only successfully initialized declarations publish new bindings;
    evaluation effects on previously published values survive failure. */
ReplResult ReplSession.submit(ReplSession session, String source) {
  Compiler c = session.compiler;
  Map names = session.names;
  ReplResult result = { .status = <rejected>, .value = void };
  c.diagnostics.reset();
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  Array added = [], ids = [];
  defer { added.free(); ids.free(); }
  List fn = NULL;
  String function_name = NULL;
  int execute = 0, prints = 0, end = source.len();
  try {
    c.tokenize(source);
    if (c.tokenizer.status() == <incomplete>) {
      result.status = <incomplete>;
      return result;
    }
    for (Token token = c.tokenizer.tokens; token.type != <eof>; token++) {
      if (token.type == <preproc> || token.type == <"$(">)
        _refuse("preprocessor and direct Lisp input are unsupported");
      if (token.type == <const> || token.type == <volatile>)
        _refuse("const and volatile need native checks outside this spike");
    }
    if (c.peek(0) == <eof>) {
      result.status = <executed>;
      return result;
    }
    if (c.peek(0) == <import> || c.peek(0) == <protocol> ||
        c.peek(0) == <"$("> || c.meta_form_is_definition() ||
        c.macro_form_is_definition() || c.keyword_form_is_definition())
      _refuse("compiler-session definitions are outside the spike");
    if (c.peek(0) == <typedef> || c.peek(0) == <struct> ||
        c.peek(0) == <union> || c.peek(0) == <enum> ||
        c.peek(0) == <extern> || c.peek(0) == <static>)
      _refuse("type and storage declarations are outside the spike");
    int declaration = c.test_declaration();
    if (!declaration) {
      String prefix = "void __repl_eval(void) {\n";
      end += prefix.len();
      c.tokenize(prefix + source + "\n}");
    }
    List node = c.parse_submission(end);
    if (!declaration) {
      fn = _result_body(node, &prints);
      execute = 1;
    }
    else {
      match (node) {
        case %(function ? (bind (binding ? ?(String name)) ?) ?): {
          Var existing;
          if (names.contains(name) || name.startswith("__repl_") ||
              c.macro_lisp.try_get(name, &existing))
            _refuse("function redeclaration is disabled");
          added.push(name);
          function_name = name;
          fn = node;
        }
      }
      if (!fn) {
        fn = _initializers(node, names, added, ids);
        execute = 1;
      }
    }
    _require_bound(fn);
    result.diagnostics = c.diagnostics();
  }
  catch %(incomplete *): {
    result.status = <incomplete>;
    return result;
  }
  catch %(malformed *): {
    result.diagnostics = c.diagnostics();
    return result;
  }
  catch %(spike (why ?why)): {
    result.diagnostics = c.diagnostics();
    result.message = why;
    return result;
  }
  result.syntax = fn;
  List forms = c.lower_comptime(fn);
  if (!forms) {
    result.message = "unsupported: " + c.lower_declined();
    return result;
  }
  result.lowered = forms;
  try {
    foreach (Var form, forms) c.macro_lisp.eval(form);
    if (execute) result.value = c.macro_lisp.eval(%(__repl_eval));
  }
  catch %(?cause *details): {
    // Discard cells for unpublished bindings before rollback reuses their IDs.
    Var storage;
    if (c.macro_lisp.try_get("C._globals", &storage)) {
      Map globals = storage;
      foreach (Var id, ids) globals.del(id);
    }
    result.status = <failed>;
    result.cause = cons(cause, details);
    return result;
  }
  if (function_name || added.len()) {
    transaction.commit();
    foreach (String name, added) names[name] = 1;
  }
  result.name = function_name;
  result.status = function_name ? <defined> : prints ? <value> : <executed>;
  return result;
}
