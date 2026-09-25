/* review.x -- structure and validation rules. */
#include <stdio.h>

typedef struct Checker { int errors; } *Checker;

typedef struct Pair { int left, right; } Pair;

typedef enum Color { RED, GREEN, BLUE } Color;

static const char *color_names[] = {"RED", "GREEN", "BLUE"};

static int count, hits, total;

void Checker.report_error(Checker c, String why) {
  c.errors++;
  raise %(bad-arg (why $why));
}

/* A return after an operation that never returns. */
int Checker.check_pair(Checker c, List node) {
  if (!node) {
    c.report_error("empty");
    return 0;
  }
  if (node.car() == <pair> && node.cdr().len() == 2 &&
      node.cadr() is <list>) {
    c.report_error("bad pair");
    return c.check_pair(node.cadr());
  }
  return 1;
}

int raise_then_return(int value) {
  if (value < 0) {
    raise %(bad-state (why "negative"));
    return 0;
  }
  return value;
}

void copy_pair(Pair *to, Pair *from) {
  to.left = from.left;
  *to = *from;
}

void count_everything(int value) {
  count += value;
  hits++;
  total = count + hits;
  count = 0;
  hits = 0;
}

void acquire_slot(int value) {
  count += value;
}

void release_slot(int value) {
  count -= value;
}

int first_name(List node) => node.car() == <name> ? 1 : 0;

int first_type(List node) => node.car() == <type> ? 1 : 0;

int first_value(List node) => node.car() == <value> ? 1 : 0;

int route_one(List node) {
  if (!node) return 0;
  printf("one\n");
  return first_name(node);
}

int route_two(List node) {
  if (!node) return 0;
  printf("two\n");
  return first_name(node);
}

int route_three(List node) {
  if (!node) return 0;
  printf("three\n");
  return first_name(node);
}

int skip_other(List nodes) {
  int total = 0;
  foreach (List node, nodes) {
    if (node.car() != <item>) continue;
    total++;
  }
  return total;
}

const char *color_name(Color color) {
  switch (color) {
    case RED: return color_names[0];
    case GREEN: return color_names[1];
    case BLUE: return color_names[2];
  }
  return NULL;
}
