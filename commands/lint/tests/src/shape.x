/* shape.x -- function shape rules and the near misses they accept. */
#include <stdio.h>

typedef struct Shape *Shape;

int spans_forty_one_lines(int value) {
  int sum = value;
  sum = sum * 31 + 1;
  sum = sum * 31 + 2;
  sum = sum * 31 + 3;
  sum = sum * 31 + 4;
  sum = sum * 31 + 5;
  sum = sum * 31 + 6;
  sum = sum * 31 + 7;
  sum = sum * 31 + 8;
  sum = sum * 31 + 9;
  sum = sum * 31 + 10;
  sum = sum * 31 + 11;
  sum = sum * 31 + 12;
  sum = sum * 31 + 13;
  sum = sum * 31 + 14;
  sum = sum * 31 + 15;
  sum = sum * 31 + 16;
  sum = sum * 31 + 17;
  sum = sum * 31 + 18;
  sum = sum * 31 + 19;
  sum = sum * 31 + 20;
  sum = sum * 31 + 21;
  sum = sum * 31 + 22;
  sum = sum * 31 + 23;
  sum = sum * 31 + 24;
  sum = sum * 31 + 25;
  sum = sum * 31 + 26;
  sum = sum * 31 + 27;
  sum = sum * 31 + 28;
  sum = sum * 31 + 29;
  sum = sum * 31 + 30;
  sum = sum * 31 + 31;
  sum = sum * 31 + 32;
  sum = sum * 31 + 33;
  sum = sum * 31 + 34;
  sum = sum * 31 + 35;
  sum = sum * 31 + 36;
  sum = sum * 31 + 37;
  return sum;
}

int spans_forty_lines(int value) {
  int sum = value;
  sum = sum * 31 + 1;
  sum = sum * 31 + 2;
  sum = sum * 31 + 3;
  sum = sum * 31 + 4;
  sum = sum * 31 + 5;
  sum = sum * 31 + 6;
  sum = sum * 31 + 7;
  sum = sum * 31 + 8;
  sum = sum * 31 + 9;
  sum = sum * 31 + 10;
  sum = sum * 31 + 11;
  sum = sum * 31 + 12;
  sum = sum * 31 + 13;
  sum = sum * 31 + 14;
  sum = sum * 31 + 15;
  sum = sum * 31 + 16;
  sum = sum * 31 + 17;
  sum = sum * 31 + 18;
  sum = sum * 31 + 19;
  sum = sum * 31 + 20;
  sum = sum * 31 + 21;
  sum = sum * 31 + 22;
  sum = sum * 31 + 23;
  sum = sum * 31 + 24;
  sum = sum * 31 + 25;
  sum = sum * 31 + 26;
  sum = sum * 31 + 27;
  sum = sum * 31 + 28;
  sum = sum * 31 + 29;
  sum = sum * 31 + 30;
  sum = sum * 31 + 31;
  sum = sum * 31 + 32;
  sum = sum * 31 + 33;
  sum = sum * 31 + 34;
  sum = sum * 31 + 35;
  sum = sum * 31 + 36;
  return sum;
}

int nest_five_deep(int value) {
  int steps = 0;
  if (value > 0) {
    for (int at = 0; at < value; at++) {
      while (steps < at) {
        if (steps % 2) {
          steps += 2;
          value--;
        }
        steps++;
      }
      steps--;
    }
    value++;
  }
  return steps + value;
}

String nest_four_deep(int value) {
  String text = "";
  if (value > 0) {
    for (int at = 0; at < value; at++) {
      if (at % 2) {
        List form = %(item @{%(value $at)});
        text = %"${text}{${form.len()}}";
      }
      text = text + ";";
    }
    text = text + ".";
  }
  return text;
}

int add_seven(int a, int b, int c, int d, int e, int f, int g) =>
  a + b + c + d + e + f + g;

int apply_six(int a, int b, int c, int d, int e, int (*op)(int, int)) =>
  op(a + b + c, d + e);

int parse_every_argument_in_a_list(void) => 30;

int Shape.parse_each_argument_in_a_list(Shape s) => 29;
