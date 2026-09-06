#include "x2c.x"

int main(void) {
  typedef Var LocalValue;
  typedef LocalValue LocalNumber;
  LocalNumber value = 3;
  value += 4;
  int number = value;
  if (number != 7) return 1;

  typedef List LocalList;
  LocalList items = %(1 2 3);
  if (items.len() != 3) return 2;

  typedef int *LocalPointer;
  const LocalPointer pointer = &number;
  *pointer = 9;
  if (number != 9) return 3;
  typedef int LocalRow[3];
  typedef LocalRow *LocalRows;
  LocalRow row = {1, 2, 3};
  LocalRows rows = &row;
  if ((*rows)[2] != 3 || sizeof(LocalRow) != 3 * sizeof(int)) return 4;
  if ((LocalNumber) number != 9) return 5;
  static LocalPointer saved = NULL;
  saved = pointer;
  if (*saved != 9) return 6;
  typedef struct Pair { int first, second; } LocalPair;
  LocalPair pair = {4, 5};
  if (pair.first + pair.second != 9) return 7;
  puts("local aliases preserve values and declarators");
  return 0;
}
