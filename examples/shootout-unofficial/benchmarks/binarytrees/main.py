#!/usr/bin/env python3

import sys


def make_tree(item, depth):
    if depth == 0:
        return item, None, None
    return (
        item,
        make_tree(item * 2 - 1, depth - 1),
        make_tree(item * 2, depth - 1),
    )


def tree_sum(tree):
    item, left, right = tree
    if left is None:
        return item
    return item + tree_sum(left) - tree_sum(right)


depth, iterations = map(int, sys.argv[1:])
print(sum(tree_sum(make_tree(item, depth)) for item in range(iterations)))
