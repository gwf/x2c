static List control_produce(List value) {
  return value;
}

static void control_consume(List value, Symbol position) {
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
    control_consume(produced, <statement>);
  }
}

static void control_assignment(List value, int choose) {
  List produced = value;
  if (choose) produced = control_produce(value);
  control_consume(produced, <block>);
}

static void control_return_consumer(List value, int choose) {
  control_consume(control_return(value, choose), <block>);
}

static void control_loop(List value, int choose) {
  while (choose) {
    List produced = control_produce(value);
    control_consume(produced, <map-entry>);
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
  control_consume(control_try_return(value), <enumerator>);
}

static List address_produce(List value) {
  return value;
}

static void address_consume(List value, Symbol position) {
  (void) value;
  (void) position;
}

static void address_mutate(List *value) {
  (void) value;
}

static void address_flow(List value) {
  List produced = address_produce(value);
  address_mutate(&produced);
  address_consume(produced, <block>);
}

static List expression_produce(List value) {
  return value;
}

static void expression_consume(List value, Symbol position) {
  (void) value;
  (void) position;
}

static void expression_flow(List value) {
  List produced;
  expression_consume(
    produced = expression_produce(value), <block>
  );
}
