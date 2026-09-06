/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/calculatorast-ported ported.x
 *   /tmp/calculatorast-ported 1000000
 */

/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef enum { NUMBER, VARIABLE, ASSIGN, BINARY } Kind;
typedef enum { ADD, SUBTRACT, MULTIPLY, DIVIDE } Operator;

static SymbolSet _operators = %<<<+> <-> <*> </>>>;

typedef struct Node *Node;
struct Node {
  Kind kind; Operator op; int value; int slot; Node left, right;
};

static Node Node.compile(List source) {
  Node node = Scope.calloc(1, sizeof(struct Node));
  match (source) {
    case %(number ?value): node.value = value.int();
    case %(variable ?name): {
      node.kind = VARIABLE;
      node.slot = name === <a> ? 0 : 1;
    }
    case %(assign ?name ?expression): {
      node.kind = ASSIGN;
      node.slot = name === <a> ? 0 : 1;
      node.right = Node.compile(expression);
    }
    case %(binary ?op ?left ?right): {
      node.kind = BINARY;
      node.op = _operators.index(op);
      node.left = Node.compile(left);
      node.right = Node.compile(right);
    }
  }
  return node;
}

static int Node.eval(Node node, int *variables) {
  if (node.kind == NUMBER) return node.value;
  if (node.kind == VARIABLE) return variables[node.slot];
  if (node.kind == ASSIGN)
    return variables[node.slot] = node.right.eval(variables);
  int a = node.left.eval(variables), b = node.right.eval(variables);
  switch (node.op) {
    case ADD: return a + b;
    case SUBTRACT: return a - b;
    case MULTIPLY: return a * b;
    default: return a / b;
  }
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  Node program[3];
  int at = 0;
  foreach(List expression, %(
    (assign a (number 7))
    (assign b (binary * (variable a) (number 6)))
    (binary + (variable b)
      (binary / (number 100) (number 5)))))
    program[at++] = Node.compile(expression);

  uint64_t checksum = 0;
  int runs = atoi(argv[1]);
  for (int run = 0; run < runs; run++) {
    int variables[2] = {0};
    for (int i = 0; i < 3; i++) checksum += program[i].eval(variables);
  }
  printf("%llu\n", (unsigned long long) checksum);
  return 0;
}
