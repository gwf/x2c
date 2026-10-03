#include "x2c.x"
#include "meta.x"

typedef struct Reporter {
  Token token;
} *Reporter;

void Reporter.report_error(
  Reporter reporter, Symbol code, String message, Token token, List notes) {
  (void) reporter;
  (void) token;
  printf("%s: %s", code.str(), message);
  foreach (Var note, notes) printf(" %s", note.repr().str());
  puts("");
}

/* Native templates carry literal syntax across translation units. */
static List disturbance = %("different" ("nested" 42));

macro Stmt $report.xform_string_assignment(Expr $c) {
  {
    String note = "String is immutable: use the copy-producing " +
                  "String.withindex, or bind a char * to write a " +
                  "transient String.malloc buffer";
    $c.report_error(
      <xform>, "String does not support bracket assignment",
      NULL, %($note));
  }
}

macro Stmt $report.macro_helper_timeout(
  Expr $c, Expr $site, Expr $limit, Expr $name) {
  $c.report_error(
    <macro>,
    "%s%g s".printf("this meta call ran longer than ", $limit),
    $site, %("function: ${$name}" "set X2C_META_TIMEOUT to a larger limit in seconds, or 0 for none"));
}

macro Stmt $report.type_destructure_list(Expr $c, Expr $source_type) {
  $c.report_error(
    <type>, "destructuring requires a List source",
    NULL, %(("source type" ${$source_type})));
}

macro Stmt $report.protocol_meta_adoption(Expr $c, Expr $origin) {
  $c.report_error(
    <protocol>, "'meta' applies only to a concrete protocol adoption",
    $origin, %("mark each adoption: meta protocol BASE(TYPE);"));
}

macro Stmt $report.type_ident_untyped(
  Expr $c, Expr $spelling, Expr $origin) {
  $c.report_error(
    <type>, %"identifier '${$spelling}' has no semantic type",
    $origin, NULL);
}

int main(void) {
  struct Reporter storage = {0};
  Reporter reporter = &storage;
  String name = "dynamic";
  List source_type = %(int);
  (void) disturbance;

  reporter.report_error(
    <type>, %"identifier '$name' has no semantic type", NULL, NULL);
  $report.type_ident_untyped(reporter, name, NULL);

  reporter.report_error(
    <protocol>, "'meta' applies only to a concrete protocol adoption", NULL,
    %("mark each adoption: meta protocol BASE(TYPE);"));
  $report.protocol_meta_adoption(reporter, NULL);

  reporter.report_error(
    <type>, "destructuring requires a List source", NULL,
    %(("source type" $source_type)));
  $report.type_destructure_list(reporter, source_type);

  reporter.report_error(
    <macro>, "%s%g s".printf("this meta call ran longer than ", 1.5),
    NULL, %("function: fixture"
      "set X2C_META_TIMEOUT to a larger limit in seconds, or 0 for none"));
  $report.macro_helper_timeout(reporter, NULL, 1.5, "fixture");

  String note = "String is immutable: use the copy-producing " +
                "String.withindex, or bind a char * to write a " +
                "transient String.malloc buffer";
  reporter.report_error(
    <xform>, "String does not support bracket assignment", NULL, %($note));
  $report.xform_string_assignment(reporter);
  return 0;
}
