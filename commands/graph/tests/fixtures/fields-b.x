typedef struct FieldOwner {
  int value;
} *FieldOwner;

int second_field_read(FieldOwner owner) {
  return owner.value;
}
