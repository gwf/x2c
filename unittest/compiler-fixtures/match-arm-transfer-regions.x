#include "x2c.x"

/* `break` in an arm leaves the match, not the cleanup region around it.
   `continue` and `return` still leave every region they cross. */

static int rounds = 0, int arms = 0;

static int deferred(Var item) {
  int n = 0;
  defer n++;
  match (item) {
    case %(keep): break;
    default: n = 1;
  }
  return n;
}

static int guarded(List items) {
  int kept = 0;
  foreach (Var item, items) {
    try {
      match (item) {
        case %(skip): continue;
        case %(keep): break;
        case %(stop): return kept + 1000;
        default: kept += 100;
      }
      arms++;
    }
    finally rounds++;
    kept++;
  }
  return kept;
}

int main(void) {
  printf("%d %d\n", deferred(%(keep)), deferred(%(other)));
  printf("%d %d %d\n", guarded(%((skip) (keep) (other))), rounds, arms);
  printf("%d %d\n", guarded(%((keep) (stop) (keep))), rounds);
  return 0;
}
