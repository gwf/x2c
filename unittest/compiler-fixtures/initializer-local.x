#include "x2c.x"
#include <netinet/in.h>

struct Record { int integer; };
struct Node { int integer; };
struct Global { String text; };
#define RECORD_SIZE sizeof(struct Record)

static void shadowed(void) {
  struct Record global = {7};
  typedef struct Record { String text; Var last; } Record;
  Record outer = {"outer", "last"};
  int outer_size = RECORD_SIZE == sizeof(outer);
  {
    typedef struct Record { Var value; String text; } Record;
    Record inner = {42, "inner"};
    String expected = "inner";
    printf("%d %d %d\n", (int)inner.value,
      (void *)inner.text == (void *)expected,
      RECORD_SIZE == sizeof(inner));
  }
  String expected = "outer";
  printf("%d %d %d %d\n", global.integer,
    (void *)outer.text == (void *)expected, outer.last is String, outer_size);
}

static void forward(void) {
  struct Node;
  struct Node *pointer;
  struct Node { String text; struct Node *next; };
  struct Node value = {"node", NULL};
  pointer = &value;
  struct Node other = {"other", pointer};
  String expected = "node";
  printf("%d %d\n", (void *)other.next.text == (void *)expected,
    value.next == NULL);
}

static void anonymous(void) {
  typedef struct { String text; Var last; } Value;
  Value named = {"named", "tail"};
  struct { String text; Var last; } direct = {"direct", 7};
  String expected = "named", other = "direct";
  printf("%d %d %d %d\n", (void *)named.text == (void *)expected,
    named.last is String, (void *)direct.text == (void *)other,
    (int)direct.last);
}

static void saved_alias(void) {
  struct Node { String value; };
  struct Node before = {"before"};
  struct Node *pointer = &before;
  typedef struct Node Saved;
  {
    typedef struct Node Nested;
    Nested nested = {"nested"};
    String expected = "nested";
    printf("%d\n", (void *)nested.value == (void *)expected);
  }
  {
    struct Node { Var value; };
    Saved original = {"saved"};
    struct Node changed = {17};
    String expected = "saved";
    printf("%d %d\n", (void *)original.value == (void *)expected,
      (int)changed.value);
  }
  struct Node after = {"after"};
  String expected = "after";
  printf("%d %d\n", pointer == &before,
    (void *)after.value == (void *)expected);
}

static void implicit_forward(void) {
  typedef struct Local Saved;
  struct Local { String text; };
  {
    struct Local { int text; };
    Saved original = {"kept"};
    struct Local changed = {7};
    String expected = "kept";
    printf("%d %d\n", (void *)original.text == (void *)expected,
      changed.text);
  }
}

static void global_alias(void) {
  typedef struct Global Saved;
  {
    struct Global { int text; };
    Saved original = {"global"};
    String expected = "global";
    printf("%d\n", (void *)original.text == (void *)expected);
  }
}

macro Statement $loop_scope() => {
  for (struct Record { String text; } value = {"macro"}; 0;)
    (void)value;
}

static void loop_scope(void) {
  for (struct Record { String text; } value = {"loop"}; 0;)
    (void)value;
  $loop_scope();
  struct Record after = {7};
  printf("%d\n", after.integer);
}

static int qualified(void) {
  struct sockaddr_in address = {0};
  address.sin_port = 37;
  const void *source = &address;
  int port = ((const struct sockaddr_in *)source)->sin_port;
  volatile struct sockaddr_in *other = &address;
  int same = ((const volatile struct sockaddr_in *)other)->sin_port;
  struct Qualified { String text; };
  const struct Qualified value = {"qualified"};
  String expected = "qualified";
  return port == 37 && same == 37 &&
    (void *)value.text == (void *)expected;
}

int main(void) {
  shadowed();
  forward();
  anonymous();
  saved_alias();
  implicit_forward();
  global_alias();
  loop_scope();
  return !qualified();
}
