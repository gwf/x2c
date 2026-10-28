/* Explicit public/private inversions in separate ordinary runs. */
static int hidden_first(void) => 1;
int public_after_private(void) => hidden_first();

#define PUBLIC_EDGE 1
int public_leaf(void) => 2;
int public_caller(void) => public_leaf();

#define PRIVATE_PATH 1
int public_target(void) => 3;
int public_through_private(void) => private_bridge();
static int private_bridge(void) => public_target();

#define PRIVATE_EDGE 1
int root(void) => private_caller();
static int private_leaf(void) => 4;
static int private_caller(void) => private_leaf();

#define CALLBACK_EDGE 1
int apply_callback(void) {
  int (*fn)(void) = callback_caller;
  return fn();
}
static int callback_leaf(void) => 5;
static int callback_caller(void) => callback_leaf();

#define SELF_RECURSION 1
int self_entry(void) => self_caller();
static int self_leaf(int n) => n ? self_leaf(n - 1) : 0;
static int self_caller(void) => self_leaf(1);

#define MIXED_PLACEMENT 1
static int mixed_helper(int n) => mixed_public(n);
int mixed_public(int n) => n ? mixed_helper(n - 1) : 0;
