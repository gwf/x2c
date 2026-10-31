#!/usr/bin/env python3
import sys

program = (
    ("assign", "a", ("number", 7)),
    ("assign", "b", ("binary", "*", ("variable", "a"), ("number", 6))),
    ("binary", "+", ("variable", "b"),
     ("binary", "/", ("number", 100), ("number", 5))),
)


def evaluate(ast, variables):
    kind = ast[0]
    if kind == "number":
        return ast[1]
    if kind == "variable":
        return variables[ast[1]]
    if kind == "assign":
        variables[ast[1]] = evaluate(ast[2], variables)
        return variables[ast[1]]
    left, right = evaluate(ast[2], variables), evaluate(ast[3], variables)
    if ast[1] == "+":
        return left + right
    if ast[1] == "-":
        return left - right
    if ast[1] == "*":
        return left * right
    return left // right


checksum = 0
for _ in range(int(sys.argv[1])):
    variables = {}
    checksum += sum(evaluate(ast, variables) for ast in program)
print(checksum)
