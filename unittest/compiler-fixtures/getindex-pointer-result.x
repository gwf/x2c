/* A typedef of a C pointer that defines `getindex` uses it for bracket
   reads, whatever its result type. A getter that yields the element's
   address makes `list[i].field` read and write the element in place,
   including a compound assignment; a by-value getter still copies. */

#include "x2c.x"

typedef struct Rec { int count; int active; } Rec;
typedef struct Recs { Rec items[4]; int n; } *Recs;
typedef struct Copies { Rec items[2]; } *Copies;

static Rec *Recs.getindex(Recs list, int index) => &list.items[index];
static Rec Copies.getindex(Copies list, int index) => list.items[index];

int main(void) {
  Recs list = calloc(1, sizeof(struct Recs));
  list.items[1].count = 3;
  Rec *one = list[1];
  int read = list[1].count;
  list[1].count += 1;
  list[1].active = 1;
  printf("%d %d %d %d\n", one.count, read, list.items[1].count,
         list.items[1].active);
  Copies copies = calloc(1, sizeof(struct Copies));
  copies.items[0].count = 5;
  Rec copy = copies[0];
  copy.count = 6;
  printf("%d %d\n", copy.count, copies.items[0].count);
  free(list);
  free(copies);
  return 0;
}
