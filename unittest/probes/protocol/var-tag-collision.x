/*  var-tag-collision.x -- two type names that encode to one Var tag

    A compact Symbol holds ten characters, so both names below become
    <tagcollisi>. Registering the second descriptor under a tag another
    type already owns is reported and aborts before main runs.
 */

#include "x2c.x"

typedef struct TagCollisionOne {
  int value;
} *TagCollisionOne;

typedef struct TagCollisionTwo {
  void *first;
  int value;
} *TagCollisionTwo;

Var TagCollisionOne.var(TagCollisionOne value) {
  return Var.new(Symbol.new("tagcollisionone"), value);
}

Var TagCollisionTwo.var(TagCollisionTwo value) {
  return Var.new(Symbol.new("tagcollisiontwo"), value);
}

TagCollisionOne Var.tagcollisionone(Var value) {
  return (TagCollisionOne) value.pointer();
}

TagCollisionTwo Var.tagcollisiontwo(Var value) {
  return (TagCollisionTwo) value.pointer();
}

protocol Var(TagCollisionOne);
protocol Var(TagCollisionTwo);

String TagCollisionOne.str(TagCollisionOne value) {
  (void) value;
  return %"one";
}

String TagCollisionTwo.str(TagCollisionTwo value) {
  (void) value;
  return %"two";
}

int main(void) {
  printf("reached main\n");
  return 0;
}
