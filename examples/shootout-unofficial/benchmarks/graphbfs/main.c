/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct Edge { int vertex; struct Edge *next; } Edge;

static void add(Edge **graph, int a, int b) {
  Edge *ab = malloc(sizeof(Edge)), *ba = malloc(sizeof(Edge));
  *ab = (Edge){b, graph[a]}; graph[a] = ab;
  *ba = (Edge){a, graph[b]}; graph[b] = ba;
}

static int bfs(Edge **graph, int n) {
  int *queue = malloc(n * sizeof(int));
  int *distance = malloc(n * sizeof(int));
  for (int i = 0; i < n; i++) distance[i] = -1;
  int head = 0, tail = 0;
  queue[tail++] = 0; distance[0] = 0;
  while (head < tail) {
    int v = queue[head++];
    for (Edge *edge = graph[v]; edge; edge = edge->next)
      if (distance[edge->vertex] < 0) {
        distance[edge->vertex] = distance[v] + 1;
        queue[tail++] = edge->vertex;
      }
  }
  int result = distance[n - 1];
  free(queue); free(distance);
  return result;
}

int main(int argc, char **argv) {
  if (argc != 4) return 2;
  int n = atoi(argv[1]), jumps = atoi(argv[2]), runs = atoi(argv[3]);
  Edge **graph = calloc(n, sizeof(Edge *));
  for (int i = 1; i < n; i++) add(graph, i - 1, i);
  uint32_t state = 1;
  for (int v = 0; v < n; v++)
    for (int j = 0; j < jumps; j++) {
      state = state * 1664525u + 1013904223u;
      int u = state % n;
      if (u != v) add(graph, v, u);
    }
  int checksum = 0;
  for (int run = 0; run < runs; run++) checksum += bfs(graph, n);
  printf("%d\n", checksum);
  for (int i = 0; i < n; i++)
    while (graph[i]) {
      Edge *next = graph[i]->next; free(graph[i]); graph[i] = next;
    }
  free(graph);
  return 0;
}
