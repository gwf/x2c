#include "x2c.x"

static int calls, finalized;
static int *saved;
static int next(void) { return ++calls; }

static int broken(int leave) {
  int result = -1;
  for (int i = 0; i < 1; i++) {
    static int value = ({
      { defer finalized++; if (leave) break; }
      next();
    });
    result = value;
  }
  return result;
}

static int continued(int leave) {
  int result = -1;
  for (int i = 0; i < 1; i++) {
    static int value = ({ if (leave) continue; next(); });
    result = value;
  }
  return result;
}

static int returned(int leave) {
  static int value = ({ if (leave) return -1; next(); });
  return value;
}

static int jumped(int leave) {
  {
    static int value = ({ if (leave) goto outside; next(); });
    return value;
  }
outside:
  return -1;
}

static int *addressed(int leave) {
  static int value = ({
    if (leave) { saved = &value; return NULL; }
    next();
  });
  return &value;
}

static int nested(int leave) {
  static int outer = ({
    static int inner = ({ if (leave) return -1; next(); });
    inner + next();
  });
  return outer;
}

int main(void) {
  int caught = 0;
  int a = broken(1);
  try { raise %(afterexit); }
  catch %(afterexit): caught++;
  int b = broken(0), c = broken(0);
  printf("%d %d %d\n", a, b, c);
  a = continued(1); b = continued(0); c = continued(0);
  printf("%d %d %d\n", a, b, c);
  a = returned(1); b = returned(0); c = returned(0);
  printf("%d %d %d\n", a, b, c);
  a = jumped(1); b = jumped(0); c = jumped(0);
  printf("%d %d %d\n", a, b, c);
  int missing = addressed(1) == NULL;
  int *address = addressed(0);
  printf("%d %d %d\n", missing, address == saved, *address);
  a = nested(1); b = nested(0); c = nested(0);
  printf("%d %d %d\n", a, b, c);
  try { raise %(afterexit); }
  catch %(afterexit): caught++;
  printf("%d %d %d\n", caught, calls, finalized);
  return 0;
}
