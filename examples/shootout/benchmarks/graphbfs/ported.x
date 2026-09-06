/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/graphbfs-ported ported.x
 *   /tmp/graphbfs-ported 50000 8 100
 */

/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct Edge { int vertex; struct Edge *next; } *Edge;

static void _add(Edge *graph, int a, int b) {
  Edge ab = Scope.malloc(sizeof(struct Edge));
  Edge ba = Scope.malloc(sizeof(struct Edge));
  *ab = (struct Edge) {b, graph[a]}; graph[a] = ab;
  *ba = (struct Edge) {a, graph[b]}; graph[b] = ba;
}

static int _bfs(Edge *graph, int n) {
  Scope.retain();
  int *queue = Scope.malloc(n * sizeof(int));
  int *distance = Scope.malloc(n * sizeof(int));
  for (int i = 0; i < n; i++) distance[i] = -1;
  int head = 0, tail = 0;
  queue[tail++] = 0; distance[0] = 0;
  while (head < tail) {
    int v = queue[head++];
    for (Edge edge = graph[v]; edge; edge = edge.next)
      if (distance[edge.vertex] < 0) {
        distance[edge.vertex] = distance[v] + 1;
        queue[tail++] = edge.vertex;
      }
  }
  int result = distance[n - 1];
  Scope.release();
  return result;
}

int main(int argc, char **argv) {
  if (argc != 4) return 2;
  int n = atoi(argv[1]), jumps = atoi(argv[2]), runs = atoi(argv[3]);
  Edge *graph = Scope.calloc(n, sizeof(Edge));
  for (int i = 1; i < n; i++) _add(graph, i - 1, i);
  uint32_t state = 1;
  for (int v = 0; v < n; v++)
    for (int j = 0; j < jumps; j++) {
      state = state * 1664525u + 1013904223u;
      int u = state % n;
      if (u != v) _add(graph, v, u);
    }
  int checksum = 0;
  for (int run = 0; run < runs; run++) checksum += _bfs(graph, n);
  printf("%d\n", checksum);
  return 0;
}
