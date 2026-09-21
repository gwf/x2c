macro expression $source_twice(expr $value) => $value + $value;

$(def source_ast_probe 1)

int String.source_probe(void) {
  return 1;
}

int source_ast_call(String text, int value) {
  return text.source_probe() + $source_twice(value);
}

List source_ast_literal(int value) {
  return %(source $value);
}

int source_ast_shadow(int value) {
  {
    int value = 3;
    value++;
  }
  return value;
}

typedef struct SourceValue {
  int value;
} SourceValue;

typedef struct SourceOwner {
  delegate SourceValue part;
} SourceOwner;

int SourceValue.int(SourceValue self) {
  return self.value;
}

int source_ast_operators(int local, SourceValue value, List values) {
  return (local * 2) + (local & 7) + value.int() + (local in values);
}

int source_ast_match(List values) {
  match (values) {
    case %(!or (left ?(int value)) (right ?(int value))):
      return value;
    default: return 0;
  }
}
