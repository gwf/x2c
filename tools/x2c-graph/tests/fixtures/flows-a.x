typedef void (*FlowCallback)(List, AstPos);

typedef struct FlowHolder {
  List value;
} *FlowHolder;

List flow_produce(List value) {
  return value;
}

void flow_consume(List value, AstPos position) {
  (void) value;
  (void) position;
}

static List flow_return_parameter(List value) {
  List local = value;
  return local;
}

static List flow_return_producer(List value) {
  return flow_produce(value);
}

static void flow_consume_parameter(List value) {
  flow_consume(value, AST_STATEMENT);
}

static void flow_direct(List value) {
  flow_consume(flow_produce(value), AST_BLOCK);
}

static void flow_locals(List value) {
  List produced = flow_produce(value);
  List assigned;
  assigned = produced;
  flow_consume(assigned, AST_FIELD);
}

static void flow_return_chain(List value) {
  List produced = flow_return_producer(value);
  List forwarded = flow_return_parameter(produced);
  flow_consume_parameter(forwarded);
}

static void flow_field_storage(FlowHolder holder, List value) {
  holder.value = flow_produce(value);
  flow_consume(holder.value, AST_BLOCK);
}

static void flow_mutation(List value) {
  List produced = flow_produce(value);
  produced += %(extra);
  flow_consume(produced, AST_BLOCK);
}

static void flow_callback(FlowCallback callback, List value) {
  callback(flow_produce(value), AST_BLOCK);
}

List flow_public_forward(List value) {
  return value;
}

List flow_ambiguous_forward(List value) {
  return value;
}

static void flow_public_chain(List value) {
  flow_consume(flow_public_forward(flow_produce(value)), AST_ENUMERATOR);
}
