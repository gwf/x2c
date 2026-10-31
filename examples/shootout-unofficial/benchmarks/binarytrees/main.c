#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct TreeNode {
  struct TreeNode *left;
  struct TreeNode *right;
  int item;
} TreeNode;

static TreeNode *new_tree(int item, int depth) {
  TreeNode *tree = malloc(sizeof(*tree));
  if (!tree) abort();
  tree->item = item;
  tree->left = depth ? new_tree(item * 2 - 1, depth - 1) : NULL;
  tree->right = depth ? new_tree(item * 2, depth - 1) : NULL;
  return tree;
}

static int tree_sum(const TreeNode *tree) {
  if (!tree->left) return tree->item;
  return tree->item + tree_sum(tree->left) - tree_sum(tree->right);
}

static void free_tree(TreeNode *tree) {
  if (tree->left) {
    free_tree(tree->left);
    free_tree(tree->right);
  }
  free(tree);
}

static int run_tree(int item, int depth) {
  TreeNode *tree = new_tree(item, depth);
  int sum = tree_sum(tree);
  free_tree(tree);
  return sum;
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int depth = atoi(argv[1]);
  int iterations = atoi(argv[2]);
  int64_t checksum = 0;
  for (int item = 0; item < iterations; item++)
    checksum += run_tree(item, depth);
  printf("%lld\n", (long long) checksum);
  return 0;
}
