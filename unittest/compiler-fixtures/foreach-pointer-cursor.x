/* A collection's own `try_next` cursor may yield a pointer, as a cursor of
   element addresses does, so a loop body changes each element in place. */

#include "x2c.x"

typedef struct Rec { int count; } Rec;
typedef struct Recs { Rec items[4]; int n; } *Recs;

static int Recs.try_next(Recs list, int &cursor, Rec *&out) {
  if (cursor >= list.n) return 0;
  out = &list.items[cursor++];
  return 1;
}

int main(void) {
  Recs list = calloc(1, sizeof(struct Recs));
  list.n = 3;
  list.items[2].count = 5;
  foreach (Rec *r in list) r.count += 1;
  printf("%d %d %d %d\n", list.items[0].count, list.items[1].count,
         list.items[2].count, list.items[3].count);
  free(list);
  return 0;
}
