typedef struct Box { int n; } Box;

static void bump(Box *box) {
  box.n++;
}

static void forward(Box &box) {
  bump(box);
}

int main(void) {
  Box box = {1};
  forward(box);
  return box.n;
}
