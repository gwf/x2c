static typedef struct Node { int value; struct Node *next; } Node;
static int counter = 1;

static int sum(Node *node) => node ? node.value + sum(node.next) : 0;

int first_total(void) {
  Node tail = {.value = 2}, head = {.value = 3, .next = &tail};
  counter += sum(&head);
  return counter;
}
