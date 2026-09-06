#include "x2c.x"

typedef struct Rec {
  int n;
} Rec;

int main(void) {
  Rec rec = { 1 };
  return (int) Array.len(&rec);
}
