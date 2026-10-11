#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

$rewrite(%(expr ("String") (segments *)))
/* A two-part interpolation joins its parts with a bar; any other declines
   to the shipped rule. */
meta Code bar_join(Code code) {
  match (code) case %(expr ? (segments ?first ?second)): {
    Array parts = [];
    foreach (List row, %($first $second)) match (row) {
      case %((!or segexp segvar) ?value): parts.push(value);
      default: parts.push(%(expr ("String") $row));
    }
    Code left = parts[0], right = parts[1];
    return $!String{ $left + "|" + $right };
  }
  return code;
}

int main(void) {
  int n = 7;
  String name = "x";
  String two = %"$name$n", three = %"a${n}b";
  printf("%s %s\n", (char *) two, (char *) three);
  return 0;
}
