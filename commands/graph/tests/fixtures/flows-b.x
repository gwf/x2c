List flow_produce(List value);
void flow_consume(List value, Symbol position);
List flow_public_forward(List value);
List flow_ambiguous_forward(List value);

static void flow_cross_unit(List value) {
  flow_consume(
    flow_public_forward(flow_produce(value)), <map-entry>
  );
}

static void flow_ambiguous(List value) {
  flow_consume(
    flow_ambiguous_forward(flow_produce(value)), <block>
  );
}
