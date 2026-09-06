#include "x2c.x"

typedef List IterParent;
typedef IterParent IterInherited;
typedef IterParent IterDelegateValues;
typedef IterParent IterOverride;

typedef struct IterDelegateOwner {
  delegate IterDelegateValues values;
} IterDelegateOwner;

static int parent_calls;
static int inherited_calls;
static int override_calls;

Iter IterParent.iter(IterParent values, Iter dest) {
  parent_calls++;
  return List.iter((List) values, dest);
}

protocol Iter(IterParent);

Iter IterInherited.iter(IterInherited values, Iter dest) {
  inherited_calls++;
  return List.iter((List) values, dest);
}

Iter IterOverride.iter(IterOverride values, Iter dest) {
  override_calls++;
  return List.iter((List) values, dest);
}

protocol Iter(IterOverride);

int main(void) {
  IterInherited inherited = %(1 2 3);
  IterDelegateValues delegate_values = %(1 2 3);
  IterOverride overridden = %(1 2 3);
  IterDelegateOwner delegated = { delegate_values };
  struct Iter delegated_storage;
  (void) delegated.iter(&delegated_storage);
  int inherited_total = 0, overridden_total = 0;
  foreach(int value, inherited) inherited_total += value;
  foreach(int value, overridden) overridden_total += value;
  printf("%d %d %d %d %d\n", inherited_total, overridden_total,
         parent_calls, inherited_calls, override_calls);
  return inherited_total == 6 && overridden_total == 6 &&
         parent_calls == 2 && inherited_calls == 0 && override_calls == 1
       ? 0 : 1;
}
