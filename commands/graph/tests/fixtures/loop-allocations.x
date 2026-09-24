static void loop_allocations(List values) {
  foreach (Var value, values) {
    Array array = %[];
    Map map = %{};
    List pair = cons(value, NULL);
    (void) array;
    (void) map;
    (void) pair;
  }
}

static void consume_list(List value) { (void) value; }

static List returned_allocation(List values) {
  while (values)
    return cons(String.new("item"), NULL);
  return NULL;
}

static void argument_allocation(List values) {
  while (values) {
    consume_list(cons(car(values), NULL));
    values = cdr(values);
  }
}

static void discarded_allocation(List values) {
  while (values) {
    (void) String.new("item");
    values = cdr(values);
  }
}

static Array one_allocation(void) {
  return %[];
}
