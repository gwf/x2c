---
section: power
tab: threads
---

```x2c
~#include <assert.h>
// Each worker squares its values and reduces them to one sum.
static Var sum_squares(const void *input, size_t bytes) {
  const int *values = input;
  double sum = 0;
  for (size_t i = 0; i < bytes / sizeof(int); i++)
    sum += (double) values[i] * values[i];
  return sum;
}

~int main(void) {
// Split the data; launch both workers before waiting for either.
int values[2][3] = {{1, 2, 3}, {4, 5, 6}};
Thread first = Thread.start(sum_squares,
  values[0], sizeof(values[0]));
Thread second = Thread.start(sum_squares,
  values[1], sizeof(values[1]));
~values[0][0] = 100;
~values[1][0] = 100;

// Combine the partial sums after both workers finish.
double left = first.join(), right = second.join();
first.free(); second.free();
printf("sum of squares: %g\n", left + right);
~assert(left == 14 && right == 77 && left + right == 91);
~return 0;
~}
```

`Thread.start` copies each batch's bytes and launches a native worker.
Both workers start before either `Thread.join` returns a result; their
partial sums combine to 91. `Thread.free` releases the finished handles.
The workers need neither shared input pointers nor a shared accumulator.
