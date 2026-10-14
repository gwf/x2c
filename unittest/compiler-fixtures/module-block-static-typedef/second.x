static class Node { int value; };
static int counter = 10;

static int sum(Node node) => node.value;

int second_total(void) {
  counter += sum(Node.new(5));
  return counter;
}

int second_boxed(void) {
  Var boxed = Node.new(7);
  Node node = boxed;
  return node.value;
}
