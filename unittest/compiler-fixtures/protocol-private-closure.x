#include "x2c.x"

typedef struct PublicBase {
  int value;
} *PublicBase;

typedef struct PublicParticipant {
  int value;
} *PublicParticipant;

protocol PublicBase(T) {
  int T.read(T);
}

int PublicBase.read(PublicBase value) {
  return value.value;
}


static typedef struct PrivateParticipant {
  int value;
} *PrivateParticipant;

static typedef struct PrivateBox {
  int value;
} *PrivateBox;

static Var PrivateBox.var(PrivateBox value) {
  return Var.new(<privatebox>, value);
}

static PrivateBox Var.privatebox(Var value) {
  return value.pointer();
}

static String PrivateBox.str(PrivateBox value) {
  return %"private:${value.value}";
}

static protocol Var(PrivateBox);

static PublicBase PrivateParticipant.publicbase(PrivateParticipant value) {
  return (PublicBase) value;
}

static macro Unit $adopt_private_participant() {
  protocol PublicBase(PrivateParticipant);
}

$adopt_private_participant();

static typedef struct PrivateBase {
  int value;
} *PrivateBase;

static protocol PrivateBase(T) {
  T T.bump(T);
}

static PrivateBase PublicParticipant.privatebase(PublicParticipant value) {
  return (PrivateBase) value;
}

static PublicParticipant PrivateBase.publicparticipant(PrivateBase value) {
  return (PublicParticipant) value;
}

static PrivateBase PrivateBase.bump(PrivateBase value) {
  value.value++;
  return value;
}

static protocol PrivateBase(PublicParticipant);

static typedef struct PrivateLeft {
  int value;
} *PrivateLeft;

static typedef struct PrivateRight {
  int value;
} *PrivateRight;

static protocol PrivateLeft(T) {
  T T.shift(T);
}

static PrivateLeft PrivateRight.privateleft(PrivateRight value) {
  return (PrivateLeft) value;
}

static PrivateRight PrivateLeft.privateright(PrivateLeft value) {
  return (PrivateRight) value;
}

static PrivateLeft PrivateLeft.shift(PrivateLeft value) {
  value.value += 2;
  return value;
}

static protocol PrivateLeft(PrivateRight);

int main(void) {
  struct PrivateParticipant private_storage = { 20 };
  PrivateParticipant private_value = &private_storage;
  struct PublicParticipant public_storage = { 21 };
  PublicParticipant public_value = &public_storage;
  struct PrivateRight right_storage = { 22 };
  PrivateRight right_value = &right_storage;
  PrivateBox box_value = Scope.malloc(sizeof(struct PrivateBox));
  box_value.value = 23;
  Var boxed = box_value;
  PrivateBox restored = boxed;
  printf("%d %d %d %s %d\n", private_value.read(),
         public_value.bump().value, right_value.shift().value,
         boxed.str(), restored.value);
  return 0;
}
