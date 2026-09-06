static List control_produce(List value) {
  return value;
}

static void control_consume(List value, AstPos position) {
  (void) value;
  (void) position;
}

static List control_return(List value, int choose) {
  if (choose) return control_produce(value);
  return value;
}

static void control_direct(List value, int choose) {
  if (choose) {
    List produced = control_produce(value);
    control_consume(produced, AST_STATEMENT);
  }
}

static void control_assignment(List value, int choose) {
  List produced = value;
  if (choose) produced = control_produce(value);
  control_consume(produced, AST_BLOCK);
}

static void control_return_consumer(List value, int choose) {
  control_consume(control_return(value, choose), AST_BLOCK);
}

static void control_loop(List value, int choose) {
  while (choose) {
    List produced = control_produce(value);
    control_consume(produced, AST_MAP_ENTRY);
    break;
  }
}

static List control_try_return(List value) {
  try {
    return control_produce(value);
  }
  finally {}
}

static void control_try_consumer(List value) {
  control_consume(control_try_return(value), AST_ENUMERATOR);
}

static List address_produce(List value) {
  return value;
}

static void address_consume(List value, AstPos position) {
  (void) value;
  (void) position;
}

static void address_mutate(List *value) {
  (void) value;
}

static void address_flow(List value) {
  List produced = address_produce(value);
  address_mutate(&produced);
  address_consume(produced, AST_BLOCK);
}

static List expression_produce(List value) {
  return value;
}

static void expression_consume(List value, AstPos position) {
  (void) value;
  (void) position;
}

static void expression_flow(List value) {
  List produced;
  expression_consume(
    produced = expression_produce(value), AST_BLOCK
  );
}
