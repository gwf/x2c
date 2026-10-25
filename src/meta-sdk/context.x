/*  context.x -- compile-time SDK context

    Copyright (c) 2026 Gary William Flake.
*/

static macro Stmt $fail.meta_sdk_invocation_missing() =>
  MetaContext.reject(
    "x2c invocation location used outside macro expansion", NULL);

static macro Stmt $fail.meta_sdk_notes_string(Expr $operation, Expr $note) =>
  _reject_value(%"${$operation} notes must be Strings", $note);

static macro Stmt $fail.meta_sdk_expansion_required(Expr $operation) =>
  MetaContext.reject(%"${$operation} used outside macro expansion", NULL);

static macro Expression $note.meta_sdk_value_notes(Expr $value) =>
  %("value: ${$value.repr()}");

// the running call

module MetaContext active;

/** Returns the context of the running compile-time call, which an
    evaluation changes with `with` for its own extent. */
MetaContext *MetaContext.current(void) => &active;

/** Returns the compiler running the current compile-time call. A slot
    function compiled into the compiler reads its facts through it. */
Compiler Compiler.expanding(void) =>
  active.expander ? active.expander : active.evaluator;

// invocations and diagnostics

/** Returns the location of the active macro invocation. */
List MetaContext.invocation_location(void) {
  if (!active.expander || !active.site)
    $fail.meta_sdk_invocation_missing();
  return active.expander.token_location(active.site);
}

/** Answers `x2c_invocation_file`, declared in `lib/meta.x`. */
String x2c_invocation_file(void) =>
  MetaContext.invocation_location().assoc(<file>);

/** Answers `x2c_invocation_line`, declared in `lib/meta.x`. */
int x2c_invocation_line(void) =>
  MetaContext.invocation_location().assoc(<line>);

/** Answers `x2c_invocation_column`, declared in `lib/meta.x`. */
int x2c_invocation_column(void) =>
  MetaContext.invocation_location().assoc(<column>);

/** Answers `x2c_diagnostic_fail`, declared in `lib/meta.x`. */
void x2c_diagnostic_fail(String message, List notes) {
  _check_notes("x2c.diagnostic.fail", notes);
  MetaContext.reject(message, notes);
}

/** Answers `x2c_diagnostic_fail_at`, declared in `lib/meta.x`. */
void x2c_diagnostic_fail_at(
  Var node, Symbol category, String message, List notes) {
  _check_notes("x2c.diagnostic.fail.at", notes);
  active.expander.report_meta_error(
    node, category, message, active.site, notes, 1);
}

/** Answers `x2c_diagnostic_error_at`, declared in `lib/meta.x`. */
void x2c_diagnostic_error_at(
  Var node, Symbol category, String message, List notes) {
  _check_notes("x2c.diagnostic.error.at", notes);
  active.expander.report_meta_error(
    node, category, message, active.site, notes, 0);
}

/** A warning reports where it is raised and returns, so a macro can keep
   expanding. Failure stays separate because it never returns. */
void x2c_diagnostic_warn(String message, List notes) {
  _check_notes("x2c.diagnostic.warn", notes);
  active.expander.report_warning(
    <macro>, message, active.expander.token, notes);
}

static void _check_notes(String operation, List notes) {
  _require_expansion(operation);
  foreach (Var note in notes)
    if (note is not <string>)
      $fail.meta_sdk_notes_string(operation, note);
}

// rejection

/** Reports `message` and `notes` at the active invocation and never
    returns, so the rejected operation's caller cannot continue with a
    missing answer. With no active invocation it is a bad state. */
void MetaContext.reject(String message, List notes) {
  Compiler c = active.evaluator;
  if (c) c.report_error(<macro>, message, active.site, notes);
  raise %(bad-state (operation "x2c SDK rejection") (reason $message));
}

// SDK operations reject use outside an active expansion.
module void _require_expansion(String operation) {
  if (!active.expander)
    $fail.meta_sdk_expansion_required(operation);
}

module void _reject_value(String message, Var value) {
  MetaContext.reject(message, $note.meta_sdk_value_notes(value));
}
