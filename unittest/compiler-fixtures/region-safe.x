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
    return b.str();
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

int main(void) {
  Scope keep = NULL;
  Scope.push(&keep);
  defer Scope.pop();
  return moved_out(&keep) != NULL && canonical_result() != NULL &&
         caller_owned() != NULL && auto_local() == 1;
}
