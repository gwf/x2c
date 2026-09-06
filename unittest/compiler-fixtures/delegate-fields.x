#include "x2c.x"

typedef struct DelegatePart {
  int value;
} DelegatePart;
typedef DelegatePart DelegatePartLeaf;

static int DelegatePart.read(DelegatePart part) {
  return part.value;
}

static void DelegatePart.bump(DelegatePart *part, int by) {
  part->value += by;
}

static int DelegatePart.pointer_read(DelegatePart *part) {
  return part->value;
}

static Self DelegatePart.same(Self part) {
  return part;
}

static DelegatePart DelegatePart.concrete(DelegatePart part) {
  return part;
}

static int DelegatePart.shadow(DelegatePart part) {
  return part.value;
}

typedef struct DelegateValueOwner {
  delegate DelegatePart part;
} DelegateValueOwner;
typedef DelegateValueOwner DelegateValueOwnerLeaf;

static int DelegateValueOwner.shadow(DelegateValueOwner owner) {
  return 88 + owner.part.value * 0;
}

typedef struct DelegatePointerOwner {
  delegate DelegatePart part;
} *DelegatePointerOwner;

typedef struct DelegatePointerFieldOwner {
  delegate DelegatePart *part;
} DelegatePointerFieldOwner;

typedef struct DelegateChain {
  delegate DelegatePointerOwner owner;
} *DelegateChain;

typedef struct DelegateChoice {
  delegate DelegatePart left, right;
} DelegateChoice;

static int DelegateChoice.read(DelegateChoice choice) {
  return 99 + choice.left.value * 0 + choice.right.value * 0;
}

typedef struct DelegateCycleA *DelegateCycleA;
typedef struct DelegateCycleB *DelegateCycleB;

struct DelegateCycleA {
  delegate DelegateCycleB b;
};

struct DelegateCycleB {
  delegate DelegateCycleA a;
};

static int DelegateCycleA.read(DelegateCycleA value) {
  return 77 + (value != NULL) * 0;
}

static int owner_calls;
static DelegateChain saved_chain;

static DelegateChain next_owner(void) {
  owner_calls++;
  return saved_chain;
}

int main(void) {
  DelegateValueOwner value = { { 1 } };
  DelegateValueOwnerLeaf leaf = { { 2 } };
  struct DelegatePointerOwner pointer_value = { { 3 } };
  DelegatePointerOwner pointer = &pointer_value;
  DelegatePointerFieldOwner pointer_field = { &pointer->part };
  struct DelegateChain chain_value = { pointer };
  DelegateChain chain = &chain_value;
  DelegateChoice choice = { { 4 }, { 5 } };
  struct DelegateCycleA cycle_a_value;
  struct DelegateCycleB cycle_b_value;
  DelegateCycleA cycle_a = &cycle_a_value;
  DelegateCycleB cycle_b = &cycle_b_value;
  cycle_a->b = cycle_b;
  cycle_b->a = cycle_a;
  saved_chain = chain;

  pointer.bump(4);
  DelegatePartLeaf same = next_owner().same();
  DelegatePart concrete = pointer.concrete();
  printf(
    "%d %d %d %d %d %d %d %d %d\n",
    value.read(), pointer.read(), pointer_field.pointer_read(),
    chain.read(), same.value, concrete.value, leaf.shadow(),
    choice.read(), cycle_a.read()
  );
  printf("owner calls: %d\n", owner_calls);
  return 0;
}
