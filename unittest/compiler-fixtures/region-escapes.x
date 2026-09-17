#include "x2c.x"

typedef struct Node { struct Node *next; Var value; } *Node;

static Node global_node;
static Map registry = NULL;

static Array _fresh_array(void) {
  Array a = [];
  a.push(1);
  return a;
}

static Node _fresh_node(void) => Scope.calloc(1, sizeof(struct Node));

static void _link(Node holder, Node item) {
  holder.next = item;
}

// An $auto array is returned.
static Array escaping_auto(void) {
  Array a = $auto([]);
  a.push(1);
  return a;
}

// A region-born value reaches a local declared outside the region.
static Array escaping_outer_local(void) {
  Array out = NULL;
  $scope() {
    Array a = _fresh_array();
    out = a;
  }
  return out;
}

// A region-born node is stored into a static.
static void escaping_static(void) {
  $scope() {
    Node n = _fresh_node();
    registry["k"] = n.value;
    global_node = n;
  }
}

// A pooled List leaves its bracket without being promoted.
static List escaping_pooled(void) {
  List.pool_retain();
  defer List.pool_release();
  List l = cons(1, NULL);
  return l;
}

// The Array is read after list_free consumed it.
static int use_after_free(void) {
  Array a = [];
  List l = a.list_free();
  return (int) a.len() + l.len();
}

// A callee stores the region-born node in its other parameter's object.
static void escaping_through_callee(Node holder) {
  $scope() {
    Node n = _fresh_node();
    _link(holder, n);
  }
}

int main(void) {
  escaping_static();
  escaping_pooled();
  escaping_through_callee(global_node);
  return escaping_auto() != NULL && escaping_outer_local() != NULL &&
         use_after_free();
}
