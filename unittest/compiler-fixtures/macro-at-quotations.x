#include "x2c.x"
#include "meta.x"

static List one(Array log, int marker) {
  log.push(marker);
  return %(expr (int) (literal (int) "3"));
}
static List many(Array log, int marker) {
  log.push(marker);
  return %((expr (int) (literal (int) "1"))
           (expr (int) (literal (int) "2")));
}
static void check_plain(List code) {
  match (code) case %("x2c.quoted" () (expr ? (call ? (args
    ("x2c.hole" ? splice ?(List items)) ("x2c.hole" ? shell ?single))))): {
    if (items.len() != 2 ||
        single !== %(expr (int) (literal (int) "3"))) abort();
    return;
  }
  abort();
}
static void check_typed(List code) {
  match (code) case %(expr (int) (call ? (args
    (expr (int) (literal (int) "3"))
    (expr (int) (literal (int) "1"))
    (expr (int) (literal (int) "2"))))): return;
  abort();
}

int main(void) {
  Array log = [];
  List plain = $!( f(@{many(log, 1)}, ${one(log, 2)}) );
  List typed = $!int{ f(${one(log, 3)}, @{many(log, 4)}) };
  check_plain(plain);
  check_typed(typed);
  if (log.len() != 4 || log[0].int() != 1 || log[1].int() != 2 ||
      log[2].int() != 3 || log[3].int() != 4) return 1;
  List runtime = $!List{ %(@{many(log, 5)}) };
  (void) runtime;
  if (log.len() != 4) return 2;
  List array = $!Array{ %[${@{many(log, 6)}}, ${${one(log, 7)}}] };
  (void) array;
  if (log.len() != 6 || log[4].int() != 6 || log[5].int() != 7) return 3;
  List sigils = $!String{ %"\$ @" };
  if (!sigils.str().contains("@") || !sigils.str().contains("$")) return 4;
  List xs = %(1 2);
  List data = %(0 @xs 3), atoms = %(@ @= ...);
  if (data.len() != 4 || atoms.len() != 3 ||
      atoms.car().symbol().str() != "@" || atoms.cadr().symbol().str() != "@=")
    return 5;
  List escaped = %(\$ \@);
  if (escaped.car().symbol().str() != "$" ||
      escaped.cadr().symbol().str() != "@") return 6;
  puts("quotation order and literal modes ok");
  return 0;
}
