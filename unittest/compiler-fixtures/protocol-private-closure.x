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

#pragma private

typedef struct PrivateParticipant {
  int value;
} *PrivateParticipant;

typedef struct PrivateBox {
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

protocol Var(PrivateBox);

static PublicBase PrivateParticipant.publicbase(PrivateParticipant value) {
  return (PublicBase) value;
}

macro Unit $adopt_private_participant() => {
  protocol PublicBase(PrivateParticipant);
}

$adopt_private_participant();

typedef struct PrivateBase {
  int value;
} *PrivateBase;

protocol PrivateBase(T) {
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

protocol PrivateBase(PublicParticipant);

typedef struct PrivateLeft {
  int value;
} *PrivateLeft;

typedef struct PrivateRight {
  int value;
} *PrivateRight;

protocol PrivateLeft(T) {
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
