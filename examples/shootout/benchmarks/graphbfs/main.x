/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/graphbfs-idiomatic main.x
 *   /tmp/graphbfs-idiomatic 50000 8 100
 */

/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "typed-array.x"
#include "typed-list.x"

static void _add(Array graph, int a, int b) {
  graph[a] = ListInt.cons(b, (ListInt) graph[a].list());
  graph[b] = ListInt.cons(a, (ListInt) graph[b].list());
}

/* Every run reuses the same queue and distance ArrayInt. Adjacency stays a
   cons chain, walked directly through its typed car and cdr. */
static int _bfs(Array graph, ArrayInt queue, ArrayInt distance) {
  int n = (int) distance.len(), head = 0, tail = 0;
  for (int i = 0; i < n; i++) distance[i] = -1;
  queue[tail++] = 0;
  distance[0] = 0;
  while (head < tail) {
    int vertex = queue[head++], next = distance[vertex] + 1;
    for (ListInt edges = (ListInt) graph[vertex].list(); edges;
         edges = edges.cdr()) {
      int neighbor = edges.car();
      if (distance[neighbor] < 0) {
        distance[neighbor] = next;
        queue[tail++] = neighbor;
      }
    }
  }
  return distance[n - 1];
}

int main(int argc, char **argv) {
  if (argc != 4) return 2;
  int n = atoi(argv[1]), jumps = atoi(argv[2]), runs = atoi(argv[3]);
  Array graph = %[];
  for (int i = 0; i < n; i++) graph.push(%());
  for (int i = 1; i < n; i++) _add(graph, i - 1, i);
  uint32_t state = 1;
  for (int vertex = 0; vertex < n; vertex++)
    for (int j = 0; j < jumps; j++) {
      state = state * 1664525u + 1013904223u;
      int neighbor = state % n;
      if (neighbor != vertex) _add(graph, vertex, neighbor);
    }
  ArrayInt distance = ArrayInt.new();
  for (int i = 0; i < n; i++) distance.push(-1);
  ArrayInt queue = distance.copy();
  int checksum = 0;
  for (int run = 0; run < runs; run++)
    checksum += _bfs(graph, queue, distance);
  printf("%d\n", checksum);
  return 0;
}
