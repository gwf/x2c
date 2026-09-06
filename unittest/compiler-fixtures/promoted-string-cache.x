#include "x2c.x"

static int dynamic_calls = 0;

char *dynamic_raw(void) {
  dynamic_calls++;
  return "dynamic";
}

inline String header_direct(void) {
  return "shared";
}

inline String header_same(void) {
  return "shared";
}

inline String header_dual(void) {
  return "dual";
}

inline String header_parens(void) {
  return ("paren");
}

inline String header_conditional(int literal) {
  return literal ? "\x41\u00A9\"C\0tail" : dynamic_raw();
}

inline Var header_boxed(void) {
  return "boxed";
}

inline List header_list(void) {
  return %(header "nested");
}

#pragma private

static String source_dual(void) {
  return "dual";
}

static String take_string(String value) {
  return value;
}

int main(void) {
  String assigned;
  assigned = "assigned";
  String direct = take_string("argument");
  String escaped = header_conditional(1);
  String dynamic = header_conditional(0);
  String before_string = header_direct();
  List before_list = header_list();
  Var boxed = header_boxed();

  String child_string = NULL;
  List child_list = NULL;
  Pool string_pool =
    String.pool_retain_named("promoted-value-cache");
  Pool list_pool = string_pool;
  PoolStats string_before = string_pool.stats();
  PoolStats list_before = list_pool.stats();
  child_string = header_same();
  child_list = header_list();
  PoolStats string_after = string_pool.stats(), list_after = list_pool.stats();
  String.pool_release();

  printf("%d %d %d %d %d %d %d %d %d %d %s %s %s %s\n",
         header_direct() == header_same(),
         header_dual() == source_dual(),
         before_string == child_string,
         before_list == child_list,
         child_list.len(),
         escaped.len(),
         escaped[0], (unsigned char) escaped[1],
         escaped[3], escaped[4],
         assigned, direct, dynamic, boxed.string());
  printf("pool %lu %lu\n",
         (unsigned long) (string_after.interned -
                          string_before.interned),
         (unsigned long) (list_after.interned -
                          list_before.interned));
  printf("calls %d parens %s nested %s\n",
         dynamic_calls, header_parens(),
         child_list.cadr().string());
  return 0;
}
