/* Direct and expanded diagnostics share the established lint rules. */
#include "diagnostics.x"
$(import "../../../../lib/error-macros.xmacro")
$(import "../../../../lib/func-errors.xmacro")

macro Stmt $user.error() { printf("returning\n"); }
macro Stmt $user.warning(Expr $c) {
  $c.report_warning(<driver>, "probe", NULL, NULL);
}

int direct_raise(void) {
  raise %(bad-arg);
  return 0;
}

int catalogue_raise(void) {
  $error.apply.args();
  return 0;
}

int direct_fallback(void) {
  $error.fallback(0) raise %(bad-arg);
}

int catalogue_fallback(void) {
  $error.fallback(0) $error.apply.args();
}

int user_fallback(void) {
  $error.fallback(0) raise %(user-cause);
}

int user_macro(void) {
  $user.error();
  return 0;
}

int dynamic_cause(void) {
  $error.arg.convert(<user-cause>, nil, 0, <value>, nil);
  return 0;
}

int direct_report(Compiler c) {
  c.report_error(<driver>, "probe", NULL, NULL);
  return 0;
}

macro Stmt $report.parse.raise_payload(Expr $c) {
  $c.report_error(
    <parse>, "raise requires a %() payload literal",
    $c.token, %("use raise %(code (key value)...);"));
}

int named_report(Compiler c) {
  $report.parse.raise_payload(c);
  return 0;
}

int returning_warning(Compiler c) {
  $user.warning(c);
  return 0;
}

int direct_validate(Compiler c, List node) {
  if (node.car() != <item>)
    c.report_error(<driver>, "probe", NULL, NULL);
  if (node.cdr().len() != 2 || node.cadr() is not <list>)
    c.report_error(<driver>, "probe", NULL, NULL);
  return 1;
}

int named_validate(Compiler c, List node) {
  if (node.car() != <item>) $report.parse.raise_payload(c);
  if (node.cdr().len() != 2 || node.cadr() is not <list>)
    $report.parse.raise_payload(c);
  return 1;
}

int conditional_direct_fallback(int active) {
  if (active) $error.fallback(0) raise %(bad-arg);
  return 1;
}

int conditional_catalogue_fallback(int active) {
  if (active) $error.fallback(0) $error.apply.args();
  return 1;
}
