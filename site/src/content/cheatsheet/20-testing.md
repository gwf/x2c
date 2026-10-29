---
title: Testing
group: Toolbox
---

```x2c
#include "test.x"

$test()
static void push_then_pop(void) {
  Array stack = auto [];
  stack.push(1);
  $expect_eq(stack[0], 1);
  stack.pop();
  $expect(stack.len() == 0);
  $expect_raises(<bad-arg>, { raise %(bad-arg); });
}

$test.main();     // prints ok NAME or FAIL NAME (file:line)
```

```sh
x2c run tests/stack_test.x        # one file
x2c test                          # every test file in the project
x2c test --filter push --list     # select by substring; list without running
```

- `$expect` keeps going after a failure, so one test can report several.
  `$expect_eq` prints both values, with a diff for multiline Strings.
- `Test.skip("reason")` marks a test skipped.
