static List alias_produce(List value) {
  return value;
}

static void alias_consume(List value, AstPos position) {
  (void) value;
  (void) position;
}

static void alias_merge(List value, int choose) {
  List produced = alias_produce(value);
  if (choose) produced = value;
  alias_consume(produced, AST_BLOCK);
}
