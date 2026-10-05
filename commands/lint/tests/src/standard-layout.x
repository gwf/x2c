#pragma indent
/* Layout source uses the same dispatch and static-call rules. */
static int _layout_unused(int n) => n + 1

int layout_arms(int choice):
  switch (choice):
    case 0:
      choice++
      return choice
    case 1:
      choice++
      choice++
      return choice
    default: return 0
