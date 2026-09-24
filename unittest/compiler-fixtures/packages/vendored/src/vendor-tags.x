#include "vendorlib-1.h"

struct Later;

typedef struct Holder {
  struct Span upstream;
  struct Later *later;
} Holder;

struct Later { int value; };

int Holder.total(Holder holder) =>
  (int) holder.upstream.lo + holder.later->value;
