#include "x2c.x"

typedef struct Node { struct Node *next; Var value; } *Node;

static Node _fresh_node(void) => Scope.calloc(1, sizeof(struct Node));

// The node is moved into a scope the caller owns.
static Node moved_out(Scope *keep) {
  $scope() {
    Node n = _fresh_node();
    Scope.move(n, keep);
    return n;
  }
  return NULL;
}

// The result is a canonical String, not the Buffer's storage.
static String canonical_result(void) {
  $scope() {
    Buffer b = Buffer.new(0);
    b.write("x");
    return b;
  }
  return NULL;
}

// Both allocations go into the caller's active region.
static Node caller_owned(void) {
  Node n = _fresh_node();
  n.next = _fresh_node();
  return n;
}

// The $auto array is used only inside its own block.
static int auto_local(void) {
  Array a = $auto([]);
  a.push(2);
  return (int) a.len();
}

static void queue_push(Node holder, Node item) {
  (void) holder, (void) item;
}

static void node_close(Node node) { (void) node; }

// A function named like a container store stores nothing.
static void named_push(Node holder) {
  $scope() {
    Node n = _fresh_node();
    queue_push(holder, n);
  }
}

// A function named like a cleanup does not own its argument.
static Node named_close(void) {
  Node n = _fresh_node();
  defer node_close(n);
  return n;
}

// A freed pointer that is assigned again is live.
static int freed_then_cleared(void) {
  char *p = Scope.malloc(4);
  Scope.free(p);
  p = NULL;
  return p == NULL;
}

// A release on an early exit leaves the region open for the fall-through.
static int early_release(int stop) {
  Scope.retain();
  Node holder = _fresh_node();
  Node n = _fresh_node();
  if (stop) {
    Scope.release();
    return 0;
  }
  holder.next = n;
  Scope.release();
  return 1;
}

// The error path frees the array the fall-through already freed and left.
static int goto_cleanup(int fail) {
  Array a = [];
  if (fail) goto failed;
  a.free();
  return 0;
failed:
  a.free();
  return -1;
}

// A destroyed Scope local names other storage once it is assigned again.
static int reused_slot(void) {
  Scope s = NULL;
  Array held = NULL;
  Scope.push(&s);
  char *first = Scope.malloc(8);
  first[0] = 'x';
  Scope.pop();
  Scope.destroy(s);
  s = Scope.new();
  Scope.push(&s);
  Array b = [];
  Scope.pop();
  held = b;
  int size = (int) held.len();
  Scope.destroy(s);
  return size;
}

int main(void) {
  Scope keep = NULL;
  Scope.push(&keep);
  defer Scope.pop();
  named_push(NULL);
  return moved_out(&keep) != NULL && canonical_result() != NULL &&
         caller_owned() != NULL && auto_local() == 1 &&
         named_close() != NULL && freed_then_cleared() &&
         early_release(0) && !goto_cleanup(0) && reused_slot() == 0;
}
