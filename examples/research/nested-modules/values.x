static int stored_answer(void) => example_state[<answer>];

int module_example_answer(void) =>
  stored_answer() + module_example_adjustment();
