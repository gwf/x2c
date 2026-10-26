#include "x2c.x"

static int subjects, guards;

static List subject(void) {
  subjects++;
  return %(pair 2 3 4);
}

static int guard(void) {
  guards++;
  return 1;
}

static int predicate(List value) =>
  value ~= %(pair ?a ?b *tail) && a.int() + b.int() == 5 && tail.len() == 1;

macro Stmt $typed_condition(Expr $subject, Name $result) {
  if ($subject ~= %(text ?(String text)) && text.len() == 4)
    $result = text.len();
  else $result = -1;
}

int main(void) {
  int result = 0, a = 90;
  if (subject() ~= %(pair ?a ?b *tail) && guard())
    result = a.int() + b.int() + tail.car().int();
  else result = -1;
  if (result != 9 || subjects != 1 || guards != 1 || a != 90) return 1;

  if (subject() ~= %(other ?a *tail) && guard()) return 2;
  else if (a != 90) return 3;
  if (guards != 1 || subjects != 2) return 4;

  if (subject() ~= %(pair ?a ?b *tail) && a.int() == 9) return 5;
  else result = a;
  if (result != 90) return 6;

  if ((%(7) ~= %(?(int a))) && a == 7) result = a;
  else return 7;
  if (result != 7 || a != 90) return 8;
  if (%("wrong") ~= %(?(int a))) return 9;

  if (%(same 3 3) ~= %(same ?a ?a)) result = a.int();
  else return 10;
  if (%(same 3 4) ~= %(same ?a ?a)) return 11;
  if (result != 3) return 12;

  if (%(pair 2 3 4) ~= %(pair ?a ?b *tail) &&
      %(text "word") ~= %(text ?(String a)) && a.len() == 4)
    result = a.len() + b.int() + tail.car().int();
  else return 13;
  if (result != 11) return 14;

  if ((%(1) ~= %(?a)) || guard()) result = a;
  if (result != 90 || guards != 1) return 15;
  if (!(%(1) ~= %(other ?a))) result = a;
  if (result != 90) return 16;
  if (!predicate(%(pair 2 3 4)) || predicate(%(other 2 3 4))) return 17;

  int visits = 0;
  for (int i = 0; i < 3; i++) {
    if (%(1) ~= %(?a)) break;
    visits++;
  }
  if (visits) return 18;
  for (int i = 0; i < 3; i++) {
    if (%(1) ~= %(?a)) continue;
    visits++;
  }
  if (visits) return 19;

  $typed_condition(%(text "word"), result);
  if (result != 4) return 20;
  Var dynamic = 7;
  if (dynamic ~= %(?a)) return 21;
  dynamic = %(8);
  if (dynamic ~= %(?(int a))) result = a;
  else return 22;
  if (result != 8) return 23;

  if (%(pair (nested 5) 6) ~= %(pair (nested ?(int a)) ?(int b)))
    result = a + b;
  else return 24;
  if (result != 11) return 25;
  if (!(%(pair 2) ~= %(!or (pair ?a) (other ?a)))) return 26;
  if (!(%() ~= %()) || (%(1) ~= %())) return 27;
  if (0 && guard() && subject() ~= %(pair ?a ?b *tail)) return 28;
  if (guards != 1) return 29;

  printf("pattern conditions passed\n");
  return 0;
}
