#include "x2c.x"

static int empty(List value) => value ~= %();
static int literal(List value) => value ~= %(alpha 7);
static int nested(List value) => value ~= %(pair (nested 5) ());
static int atom(List value) => value ~= %(a-long-exact-Atom-name);
static int integer(List value) => value ~= %(7);
static int singleton_list(List value) => value ~= %((alpha 7));
static int text(List value) => value ~= %(pair "word");
static int wide(List value) => value ~= %(4294967296l);
static int dynamic_empty(Var value) => value ~= %();

static int calls;
static List subject(void) { calls++; return %(alpha 7); }

int main(void) {
  List values[] = {%(), %(alpha), %(alpha 7), %(alpha 8), %(alpha 7 9),
    %(pair (nested 5) ()), %(pair (nested 5 6) ()), %(pair nested ()),
    %(a-long-exact-Atom-name), %(a-long-exact-atom-name)};
  for (int i = 0; i < 10; i++) {
    List value = values[i];
    if (empty(value) != (value == %())) return 1;
    if (literal(value) != (value == %(alpha 7))) return 2;
    if (nested(value) != (value == %(pair (nested 5) ()))) return 3;
    if (atom(value) != (value == %(a-long-exact-Atom-name))) return 4;
  }
  if (!(subject() ~= %(alpha 7)) || calls != 1) return 5;
  if (!dynamic_empty(%()) || dynamic_empty(0) || dynamic_empty(%(1)))
    return 6;

  // Value matching must survive distinct String and wide-number identities.
  String copy = String.malloc(5);
  memcpy(copy, "word", 5);
  List words = %(pair $copy);
  if (!text(words) || words == %(pair "word")) return 7;
  List number = %($(Var.box_long(4294967296l)));
  if (!wide(number) || number == %(4294967296l)) return 8;
  copy.free();

  if (!(%(alpha 7) ~= %(alpha ?))) return 9;
  if (!(%(alpha 7 8) ~= %(alpha *))) return 10;
  if (!(%(beta) ~= %(!or (alpha) (beta)))) return 11;
  if (!(%((beta)) ~= %((!or (alpha) (beta))))) return 12;
  if (!(%((?x)) ~= %((!quote (?x))))) return 13;
  if (!integer(%(7)) || integer(%(8)) || integer(%(7 8))) return 14;

  Pool isolated = Pool.retain(NULL);
  List tail = List.cons_in(isolated, 7, NULL);
  List separate = List.cons_in(isolated, <alpha>, tail);
  if (!literal(separate) || separate == %(alpha 7)) return 15;
  List single = List.cons_in(isolated, 7, NULL);
  if (!integer(single)) return 16;
  List separate_nested = List.cons_in(isolated, separate, NULL);
  if (!singleton_list(separate_nested) || separate_nested == %((alpha 7)))
    return 17;
  isolated.release();
  puts("constant pattern equality passed");
  return 0;
}
