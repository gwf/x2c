module int example_delta(void) => 1;

module {
  "adjustment/first.x",
  "adjustment/second.x",
}

int module_example_adjustment(void) =>
  module_example_first() + module_example_second();
