#include "x2c.x"

typedef struct Node *Node;

macro Statement $require(Expr $value) {
  if (!$value) return;
}

static int add(int &?value) {
  if (!value) return -1;
  value += 2;
  return value;
}

static int forward(int &?value) => add(value);

static int forward_func(int &?value) {
  Func function = add;
  return function(value).int();
}

static int node_state(Node &?node) {
  if (node == NULL) return 1;
  return node == NULL ? 2 : 3;
}

static void set_with_macro(int &?value) {
  $require(value);
  value = 9;
}

int main(void) {
  int value = 3;
  if (forward(value) != 5 || value != 5) return 1;
  if (forward(NULL) != -1) return 2;

  Node node = NULL;
  if (node_state(node) != 2 || node_state(NULL) != 1) return 3;

  Func function = add;
  if (function(value).int() != 7 || value != 7) return 4;
  if (function(NULL).int() != -1) return 5;
  int forwarded = 1;
  if (forward_func(forwarded) != 3 || forwarded != 3 ||
      forward_func(NULL) != -1) return 7;
  Func lambda = %!(int &?arg) => {
    if (!arg) return -1;
    arg += 2;
    return arg;
  };
  int captured = 1;
  if (lambda(captured).int() != 3 || captured != 3 ||
      lambda(NULL).int() != -1) return 8;
  set_with_macro(value);
  set_with_macro(NULL);
  if (value != 9) return 6;
  int caught = 0;
  try function(7);
  catch %(bad-types *): caught++;
  return caught != 1;
}
