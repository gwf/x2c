#include "x2c.x"

int main(void) {
  List break_inputs = %( ((ok)) ((ok)) );
  int matched = 0, after = 0;
  foreach(Var item, break_inputs) {
    List value = item;
    match (value) {
      case %( (ok) ): {
        matched++;
        break;
      }
    }
    after++;
  }

  List continue_inputs = %( ((skip)) ((keep)) ((skip)) );
  int visited = 0, accepted = 0;
  foreach(Var item, continue_inputs) {
    List value = item;
    visited++;
    match (value) {
      case %( (skip) ):
        continue;
    }
    accepted++;
  }
  printf("%d %d %d %d\n", matched, after, visited, accepted);
  return matched == 2 && after == 2 && visited == 3 && accepted == 1 ? 0 : 1;
}
