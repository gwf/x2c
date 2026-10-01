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
$(import "../../src/error-reports.xmacro")

int main(void) {
  struct Reporter storage = {0};
  Reporter reporter = &storage;
  String name = "dynamic";
  List source_type = %(int);
  (void) disturbance;

  reporter.report_error(
    <type>, %"identifier '$name' has no semantic type", NULL, NULL);
  $report(reporter, "type.ident.untyped", name, NULL);

  reporter.report_error(
    <protocol>, "'meta' applies only to a concrete protocol adoption", NULL,
    %("mark each adoption: meta protocol BASE(TYPE);"));
  $report(reporter, "protocol.meta.adoption", NULL);

  reporter.report_error(
    <type>, "destructuring requires a List source", NULL,
    %(("source type" $source_type)));
  $report(reporter, "type.destructure.list", source_type);

  reporter.report_error(
    <macro>, "%s%g s".printf("this meta call ran longer than ", 1.5),
    NULL, %("function: fixture"
      "set X2C_META_TIMEOUT to a larger limit in seconds, or 0 for none"));
  $report(reporter, "macro.helper.timeout", NULL, 1.5, "fixture");

  String note = "String is immutable: use the copy-producing " +
                "String.withindex, or bind a char * to write a " +
                "transient String.malloc buffer";
  reporter.report_error(
    <xform>, "String does not support bracket assignment", NULL, %($note));
  $report(reporter, "xform.string.assignment");
  return 0;
}
