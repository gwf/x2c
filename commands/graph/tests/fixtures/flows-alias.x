static List alias_produce(List value) {
  return value;
}

static void alias_consume(List value, Symbol position) {
  (void) value;
  (void) position;
}

static void alias_merge(List value, int choose) {
  List produced = alias_produce(value);
  if (choose) produced = value;
  alias_consume(produced, <block>);
}
