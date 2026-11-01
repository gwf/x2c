#!/usr/bin/env python3
import sys
from collections import deque

n, jumps, runs = map(int, sys.argv[1:])
graph = [[] for _ in range(n)]


def add(a, b):
    graph[a].append(b)
    graph[b].append(a)


for vertex in range(1, n):
    add(vertex - 1, vertex)
state = 1
for vertex in range(n):
    for _ in range(jumps):
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        neighbor = state % n
        if neighbor != vertex:
            add(vertex, neighbor)


def bfs():
    distance = [-1] * n
    distance[0] = 0
    queue = deque([0])
    while queue:
        vertex = queue.popleft()
        for neighbor in graph[vertex]:
            if distance[neighbor] < 0:
                distance[neighbor] = distance[vertex] + 1
                queue.append(neighbor)
    return distance[-1]


print(sum(bfs() for _ in range(runs)))
