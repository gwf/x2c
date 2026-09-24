typedef struct FieldOwner {
  int value;
  int values[2];
  Map entries;
} *FieldOwner;

typedef struct OtherOwner {
  int value;
} *OtherOwner;

static int field_read(FieldOwner owner) {
  return owner.value;
}

static int field_double_read(FieldOwner owner) {
  return owner.value + owner.value;
}

static void field_assign(FieldOwner owner) {
  owner.value = 1;
}

static void field_replace_parameter(FieldOwner owner, int value) {
  owner.value = value;
}

static void field_replace_and_read(FieldOwner owner) {
  owner.value = owner.value + 1;
}

static void field_compound(FieldOwner owner) {
  owner.value += 1;
}

static void field_prefix(FieldOwner owner) {
  ++owner.value;
}

static void field_postfix(FieldOwner owner) {
  owner.value++;
}

static int other_field_read(OtherOwner owner) {
  return owner.value;
}

static void field_indexed(FieldOwner owner, OtherOwner selector) {
  owner.values[selector.value] = 1;
}

static void field_mapped(FieldOwner owner) {
  owner.entries[%(key)] = 1;
}
