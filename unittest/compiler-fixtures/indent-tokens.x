#pragma indent
// The layout pass inserts zero-width braces, semicolons, and parentheses.
int f(int x):
  if x > 0: return 1
  else:
    x = -x
  do:
    int y = x
  return x > 1 ? 2 : 3
