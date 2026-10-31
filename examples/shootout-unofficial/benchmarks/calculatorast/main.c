/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef enum { NUMBER, VARIABLE, BINARY, ASSIGN } Kind;
typedef struct Node {
  Kind kind;
  int value;
  char name;
  char op;
  struct Node *left, *right;
} Node;

static Node *node(Kind kind, int value, char name, char op,
                  Node *left, Node *right) {
  Node *result = malloc(sizeof(Node));
  *result = (Node){kind, value, name, op, left, right};
  return result;
}

static int eval(Node *ast, int variables[26]) {
  if (ast->kind == NUMBER) return ast->value;
  if (ast->kind == VARIABLE) return variables[ast->name - 'a'];
  if (ast->kind == ASSIGN)
    return variables[ast->name - 'a'] = eval(ast->right, variables);
  int left = eval(ast->left, variables);
  int right = eval(ast->right, variables);
  switch (ast->op) {
    case '+': return left + right;
    case '-': return left - right;
    case '*': return left * right;
    default: return left / right;
  }
}

static void release(Node *ast) {
  if (!ast) return;
  release(ast->left); release(ast->right); free(ast);
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  int runs = atoi(argv[1]);
  Node *program[] = {
    node(ASSIGN, 0, 'a', 0, 0, node(NUMBER, 7, 0, 0, 0, 0)),
    node(ASSIGN, 0, 'b', 0, 0,
      node(BINARY, 0, 0, '*', node(VARIABLE, 0, 'a', 0, 0, 0),
           node(NUMBER, 6, 0, 0, 0, 0))),
    node(BINARY, 0, 0, '+', node(VARIABLE, 0, 'b', 0, 0, 0),
         node(BINARY, 0, 0, '/', node(NUMBER, 100, 0, 0, 0, 0),
              node(NUMBER, 5, 0, 0, 0, 0)))
  };
  uint64_t checksum = 0;
  for (int run = 0; run < runs; run++) {
    int variables[26] = {0};
    for (int i = 0; i < 3; i++) checksum += eval(program[i], variables);
  }
  printf("%llu\n", (unsigned long long)checksum);
  for (int i = 0; i < 3; i++) release(program[i]);
  return 0;
}
