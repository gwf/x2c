#include "x2c.x"

static int called, index_calls;

static List replacement(List input, Var pattern) {
  called++;
  return %(sentinel);
}

static int pick_index(void) {
  index_calls++;
  return 0;
}

int main(void) {
  int sentinels = 0;
  {
    List (*List_match)(List, Var) = replacement;
    List pattern = %(anything);
    sentinels += List_match(%(hello), %(anything)).car() == <sentinel>;
    sentinels += List_match(%(hello), pattern).car() == <sentinel>;
  }
  {
    List (*List_match[1])(List, Var) = { replacement };
    sentinels +=
      List_match[pick_index()](%(hello), %(anything)).car() == <sentinel>;
  }
  {
    struct { List (*call)(List, Var); } List_search = { replacement };
    sentinels += List_search.call(%(hello), %(anything)).car() == <sentinel>;
  }
  List actual = (List_match)(%(hello), %(?value));
  int matched = actual.assoc(<?value>) == <hello>;
  printf("%d %d %d %d\n", called, index_calls, sentinels, matched);
  return called == 4 && index_calls == 1 && sentinels == 4 && matched ? 0 : 1;
}
