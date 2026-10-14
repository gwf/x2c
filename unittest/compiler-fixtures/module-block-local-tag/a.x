static typedef struct Node { int value; struct Node *next; } Node;
module int a_run(void) {
  struct Node { double x, y, z; };
  return (int) sizeof(struct Node);
}
