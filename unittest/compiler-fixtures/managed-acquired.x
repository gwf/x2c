#include "x2c.x"

typedef int Ticket;
void Ticket.cleanup(Ticket ticket) { printf("release %d\n", ticket); }
protocol Cleanup(Ticket);
typedef Ticket ChildTicket;

typedef struct Value { int id; } Value;
void Value.cleanup(Value value) { printf("value %d\n", value.id); }
protocol Cleanup(Value);

typedef const Ticket FrozenTicket;
void FrozenTicket.cleanup(FrozenTicket ticket) { printf("frozen %d\n", ticket); }
int FrozenTicket.current(FrozenTicket ticket) { return ticket; }
protocol Cleanup(FrozenTicket);
typedef const Value FrozenValue;
void FrozenValue.cleanup(FrozenValue value) { printf("frozen value %d\n", value.id); }
protocol Cleanup(FrozenValue);
typedef int *const FixedPointer;
typedef volatile Ticket SharedTicket;
typedef const unsigned char FrozenByte;
static struct { int id; } prior = { 29 };
static const struct { int id; } frozen_prior = { 40 };

static void lazy_scope(int allocate) {
  auto Scope frame = NULL;
  if (allocate) Scope.malloc_in(&frame, 8);
}

macro Stmt $inferred(Name $name, Expr $value) { auto $name = $value; }
macro Stmt $managed_value(Name $name, Expr $value) {
  Ticket $name = auto $value;
}
macro Stmt $constructed_auto(Name $name, Expr $value) {
  @(list (list 'declare '(auto)
    (list 'bindings (list 'op '= (list 'bind $name nil) $value))))
}

static int successor(int value) { return value + 1; }

int main(void) {
  {
    Ticket ticket = $auto((Ticket) 1);
    ticket = 2;
    printf("current %d\n", ticket);
  }
  {
    const Ticket ticket = $auto((Ticket) 3);
    printf("const %d\n", ticket);
  }
  {
    Ticket ticket = 4;
    defer ticket.cleanup();
    ticket = 5;
  }
  {
    Value value = $auto((Value) { .id = 6 });
    value.id = 7;
    printf("current value %d\n", value.id);
  }
  {
    volatile Ticket ticket = $auto((Ticket) 8);
    ticket = 9;
    printf("volatile %d\n", ticket);
  }
  {
    auto Ticket ticket = 10, second = 12;
    ticket = 11;
    (void) second;
  }
  {
    Ticket ticket = auto (Ticket) 13;
    ticket = 14;
    printf("initializer %d\n", ticket);
  }
  {
    auto ticket = (ChildTicket) 15;
    ticket = 16;
    auto Value value = { .id = 17 };
    value.id = 18;
  }
  {
    const Ticket original = 19;
    auto copy = original;
    copy = 20;
    auto const fixed = (Ticket) 21;
    printf("qualified %d\n", fixed);
  }
  {
    $inferred(ticket, (Ticket) 22);
    ticket = 23;
    $managed_value(saved, (Ticket) 24);
    saved = 25;
    printf("macro %d\n", saved);
    $constructed_auto(built, (Ticket) 26);
    built = 27;
  }
  {
    auto array = [];
    array.push(7);
    auto number = (unsigned char) 250;
    auto text = (String) "pooled";
    auto list = %(pooled);
    const int numbers[2] = { 3, 4 };
    auto pointer = numbers;
    auto function = successor;
    int plain = auto 9, old = $auto(8);
    auto aggregate = (struct { int id; }) { 28 };
    int evaluations = 0;
    auto previous = (evaluations++, prior);
    auto address = &prior;
    auto mutable_copy = frozen_prior;
    mutable_copy.id = 41;
    printf("inferred %d %d %d %d %d %d\n", array[0].int(),
      (int) sizeof(number), text == "pooled", list.len(),
      function(pointer[1]), plain + old);
    printf("aggregate %d\n", aggregate.id);
    printf("anonymous %d %d %d\n", previous.id, address.id, evaluations);
    printf("anonymous copy %d\n", mutable_copy.id);
  }
  {
    auto ticket = (FrozenTicket) 30;
    ticket = 31;
    auto value = (FrozenValue) { .id = 32 };
    value.id = 33;
    int first = 34, second = 35;
    auto pointer = (FixedPointer) &first;
    pointer = &second;
    *pointer = 36;
    printf("projection %d %d\n", ticket.current(), second);
    auto inherited = (SharedTicket) 37;
    inherited = 38;
    auto const fixed = (FrozenTicket) 39;
    auto narrow = (FrozenByte) 250;
    narrow = 251;
    printf("projected const %d %d %d\n", fixed.current(),
      (int) sizeof(narrow), narrow);
  }
  ScopeStats before = Scope.stats();
  lazy_scope(0);
  ScopeStats empty = Scope.stats();
  lazy_scope(1);
  ScopeStats populated = Scope.stats();
  printf("lazy %d %d\n",
    empty.scope_creations == before.scope_creations,
    populated.live_allocations == before.live_allocations &&
    populated.live_scopes == before.live_scopes);
  return 0;
}
