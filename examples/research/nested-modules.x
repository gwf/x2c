/* Nested modules: shared parent state and private child operations. */
module Map example_state = {answer: 40};

module macro Expression $example.value(Expr $value) => $value;

module {
  "nested-modules/values.x",
  "nested-modules/adjustment.x",
}

int main(void) => module_example_answer() == 42 ? 0 : 1;
