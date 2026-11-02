#include "x2c.x"
typedef void *VoidPointer;
static int read_optional(int &?value) {
  if (!value) return 77;
  return value;
}
static int compare_optional(int &?value) => value == NULL;
int main(void) {
  Func f = read_optional;
  int caught = 0;
  long zero = 0;
  try f((void)0); catch %(bad-types *): caught++;
  try f((void **)0); catch %(bad-types *): caught++;
  try f((void *)zero); catch %(bad-types *): caught++;
  try f((long)(void *)0); catch %(bad-types *): caught++;
  printf("rejected %d\n", caught);
  printf("absent %d %d %d\n", f((void *)0).int(),
    f((VoidPointer)0).int(), f((void *)(1 - 1)).int());
  int value = 7;
  printf("compare %d %d\n", compare_optional(NULL), compare_optional(value));
  auto runtime_right = 1 ? &value : (void *)zero;
  auto runtime_left = 0 ? (void *)zero : &value;
  printf("runtime pointers %d %d\n",
    _Generic(runtime_right, void *: 1, default: 0),
    _Generic(runtime_left, void *: 1, default: 0));
  return 0;
}
