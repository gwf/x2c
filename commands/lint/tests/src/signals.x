/* Positive examples for validation, matching, and enum table signals. */
int check_node(List node) {
  Array items = [];
  if ((void *) items == NULL) return 0;
  if (node.len() == 0) return 0;
  if (node.car() == <empty>) return 0;
  if (node.cdr().len() == 0) return 0;
  return 1;
}

int grow_items(Array items, Var value) {
  int expected = items.len() + 1;
  items.push(value);
  if (items.len() != expected) return 0;
  return 1;
}

Var capture_value(List node) {
  List bindings = node.match(%(value ?value));
  Var value = bindings.assoc(<?value>);
  return value;
}

enum Color { RED, GREEN, BLUE };
static Color colors[] = { RED, GREEN, BLUE };
int color_value(Color color) {
  switch (color) {
    case RED: return 1;
    case GREEN: return 2;
    case BLUE: return 3;
  }
  return 0;
}

void shape_error(void) { raise %(bad-arg); }
int validate_tree(List node) {
  if (node.car() != <tree>)
    shape_error();
  switch (node.len()) {
    case 0: return validate_tree(node.cdr());
    case 1: return validate_tree(node.cdr());
    case 2: return validate_tree(node.cdr());
    case 3: return validate_tree(node.cdr());
    case 4: return validate_tree(node.cdr());
    case 5: return validate_tree(node.cdr());
    case 6: return validate_tree(node.cdr());
    case 7: return validate_tree(node.cdr());
    case 8: return validate_tree(node.cdr());
    case 9: return validate_tree(node.cdr());
    case 10: return validate_tree(node.cdr());
    case 11: return validate_tree(node.cdr());
    case 12: return validate_tree(node.cdr());
    case 13: return validate_tree(node.cdr());
    case 14: return validate_tree(node.cdr());
    case 15: return validate_tree(node.cdr());
    case 16: return validate_tree(node.cdr());
    case 17: return validate_tree(node.cdr());
    case 18: return validate_tree(node.cdr());
    case 19: return validate_tree(node.cdr());
    case 20: return validate_tree(node.cdr());
    case 21: return validate_tree(node.cdr());
    case 22: return validate_tree(node.cdr());
    case 23: return validate_tree(node.cdr());
    case 24: return validate_tree(node.cdr());
    case 25: return validate_tree(node.cdr());
    case 26: return validate_tree(node.cdr());
    case 27: return validate_tree(node.cdr());
    case 28: return validate_tree(node.cdr());
    case 29: return validate_tree(node.cdr());
    case 30: return validate_tree(node.cdr());
    case 31: return validate_tree(node.cdr());
    case 32: return validate_tree(node.cdr());
  }
  return 0;
}
