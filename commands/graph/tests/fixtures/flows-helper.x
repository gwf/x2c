static List helper_produce(List value) {
  return value;
}

static void helper_consume(List value, Symbol position) {
  (void) value;
  (void) position;
}

static List helper_return_parameter(List value) {
  List local = value;
  return local;
}

static List helper_return_producer(List value) {
  return helper_produce(value);
}

static void helper_consume_parameter(List value) {
  helper_consume(value, <statement>);
}

static void helper_chain(List value) {
  List produced = helper_return_producer(value);
  List forwarded = helper_return_parameter(produced);
  helper_consume_parameter(forwarded);
}
