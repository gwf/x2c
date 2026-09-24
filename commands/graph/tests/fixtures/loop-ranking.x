static void rank_scoped_array(List values) {
  while (values) {
    Array array = %[];
    (void) array;
  }
}

static void rank_scoped_map(List values) {
  while (values) {
    Map map = %{};
    (void) map;
  }
}

static void rank_discarded(List values) {
  while (values) (void) String.new("discarded");
}

static String _rank_helper_value(void) {
  return String.new("helper");
}

static void rank_helper(List values) {
  while (values) {
    String value = _rank_helper_value();
    (void) value;
  }
}

static void rank_total(List values) {
  while (values) return (void) cons(String.new("two"), NULL);
}

static void rank_depth(List values) {
  while (values)
    while (values) return (void) cons(void, NULL);
}

static void tie_01(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_02(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_03(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_04(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_05(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_06(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_07(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_08(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_09(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_10(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_11(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_12(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_13(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_14(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_15(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_16(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_17(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_18(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_19(List values) {
  while (values) return (void) cons(void, NULL);
}
static void tie_20(List values) {
  while (values) return (void) cons(void, NULL);
}
