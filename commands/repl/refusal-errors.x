#pragma once

/* Session refusals keep their existing raise and transaction boundary. */

macro Stmt $refusal.binding.unresolved(Expr $name) =>
  _refuse(%"unresolved identifier: ${$name}");

macro Stmt $refusal.storage.native() =>
  _refuse("static, extern, and threaded storage need native execution");

macro Stmt $refusal.binding.redefined() =>
  _refuse("redeclaration is disabled; use assignment");

macro Stmt $refusal.binding.initializer() =>
  _refuse("top-level values need an initializer and a simple binding");

macro Stmt $refusal.form.unsupported() =>
  _refuse("this top-level form is outside the REPL subset");

macro Stmt $refusal.input.unsupported() =>
  _refuse("preprocessor and direct Lisp input are unsupported");

macro Stmt $refusal.qualifier.native() =>
  _refuse("const and volatile need native checks outside the REPL");

macro Stmt $refusal.definition.unsupported() =>
  _refuse("compiler-session definitions are outside the REPL subset");

macro Stmt $refusal.declaration.unsupported() =>
  _refuse("type and storage declarations are outside the REPL subset");

macro Stmt $refusal.function.redefined() =>
  _refuse("function redeclaration is disabled");

macro Stmt $refusal.function.missing(Expr $name) =>
  _refuse(%"no native function is available for ${$name}");

macro Stmt $refusal.type.redefined() =>
  _refuse("a type cannot be redefined; the session keeps its layout");
