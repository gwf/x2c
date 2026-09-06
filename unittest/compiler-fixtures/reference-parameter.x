typedef struct Counter {
  int value;
} Counter;

static void increment(int &value) {
  value += 1;
}

static void swap(int &left, int &right) {
  int temporary = left;
  left = right;
  right = temporary;
}

static void increment_twice(int &value) {
  increment(value);
  increment(value);
}

static void advance(Counter &counter, int amount) {
  counter.value += amount;
}

int main(void) {
  int first = 4, second = 9;
  Counter counter = { 10 };
  increment(first);
  swap(first, second);
  increment_twice(second);
  advance(counter, 7);
  printf("%d %d %d\n", first, second, counter.value);
  return 0;
}
