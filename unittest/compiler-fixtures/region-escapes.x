#include "x2c.x"

typedef struct Node { struct Node *next; Var value; } *Node;

static Node global_node;
static Map registry = NULL;
static List saved = NULL;

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
  Pool.open();
  defer Pool.close();
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

// A String pointer block is region storage, not a canonical String.
static String *escaping_string_block(void) {
  $scope() {
    String *names = Scope.calloc(4, sizeof(String));
    return names;
  }
  return NULL;
}

// A cons cell holding a region-born Array is stored into a static.
static void escaping_static_cons(void) {
  $scope() {
    Array a = [];
    saved = cons(a, saved);
  }
}

// The node moves into a Scope this function destroys before returning it.
static Node escaping_destroyed_slot(void) {
  Scope keep = NULL;
  Node n = NULL;
  $scope() {
    n = _fresh_node();
    Scope.move(n, &keep);
  }
  Scope.destroy(keep);
  return n;
}

// Either arm of a conditional can be returned.
static Array escaping_conditional(int flag) {
  $scope() {
    Array a = [];
    return flag ? a : NULL;
  }
  return NULL;
}

// A List cell outlives the region of the Array it holds.
static List escaping_list_literal(void) {
  $scope() {
    Array a = [];
    return %($a);
  }
  return NULL;
}

// A closure that captures an $auto Array is returned.
static Func escaping_closure(void) {
  Array a = $auto([]);
  return %!() => a.len();
}

static void _keep_two(Var first, Var second) {
  saved = cons(first, cons(second, saved));
}

// One statement sinks the same value twice, and reports it once.
static void escaping_twice(void) {
  $scope() {
    Array a = [];
    _keep_two(a, a);
  }
}

int main(void) {
  escaping_static();
  escaping_pooled();
  escaping_through_callee(global_node);
  escaping_static_cons();
  escaping_twice();
  return escaping_auto() != NULL && escaping_outer_local() != NULL &&
         use_after_free() && escaping_string_block() != NULL &&
         escaping_destroyed_slot() != NULL &&
         escaping_conditional(1) != NULL &&
         escaping_list_literal() != NULL && escaping_closure() != NULL;
}
