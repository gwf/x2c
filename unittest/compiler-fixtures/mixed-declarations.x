#include "x2c.x"

int mixed_global_i = 1, float mixed_global_x = 2.5,
    char mixed_global_c = 'g';

typedef struct MixedFields {
  int i, float x, char c;
} MixedFields;

typedef float MixedValue;
typedef List MixedValues;

int main(void) {
  int i = 3, float x = 4.5, char c = 'b';
  MixedFields fields = { 5, 6.5, 'f' };
  int ordinary = 7, MixedValue = 8;
  {
    int count = 9, MixedValues values = %(10);
    printf("%d %ld\n", count, values.car().integer());
  }
  printf("%d %.1f %c %d %.1f %c %d %.1f %c %d\n",
         mixed_global_i, mixed_global_x, mixed_global_c,
         i, x, c, fields.i, fields.x, fields.c,
         ordinary + MixedValue);
  return 0;
}
