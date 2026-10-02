#include "x2c.x"
#include <string.h>
#include <errno.h>
char *strerror(int error);

typedef struct Reporter { Token token; } *Reporter;
static int reports, shadow_calls;
void Reporter.report_error(Reporter reporter, Symbol code, String message,
                          Token site, List notes) {
  (void) reporter; (void) code; (void) message; (void) site;
  if (notes.len() == 2 &&
      notes[1].string() == %"reason: ${String.new(strerror(ENOENT))}")
    reports++;
}
static char *alternate(int error) { (void) error; shadow_calls++; return "shadow"; }
macro Statement $report.emit_file_write(Expr $c, Expr $failure) {
  {
    String reason = String.new(strerror((int) $failure.assoc(<"errno">)));
    $c.report_error(
      <emit>, "failed to write generated file",
      $c.token, %("file: ${$failure.assoc(<path>)}" "reason: $reason"));
  }
}

int main(void) {
  struct Reporter storage = {0}; Reporter reporter = &storage;
  char *(*strerror)(int) = alternate;
  String reason = "caller";
  List failure = %((errno ${(int) ENOENT}) (path "probe"));
  $report.emit_file_write(reporter, failure);
  printf("named reports retain definition bindings and caller locals\n");
  return reports != 1 || shadow_calls != 0 || reason != %"caller";
}
