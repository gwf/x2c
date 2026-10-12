#include "x2c.x"

typedef int Ticket;
void Ticket.cleanup(Ticket ticket) { printf("release %d\n", ticket); }
protocol Cleanup(Ticket);

typedef struct Value { int id; } Value;
void Value.cleanup(Value value) { printf("value %d\n", value.id); }
protocol Cleanup(Value);

static void lazy_scope(int allocate) {
  Scope frame = NULL;
  defer frame.cleanup();
  if (allocate) Scope.malloc_in(&frame, 8);
}

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
