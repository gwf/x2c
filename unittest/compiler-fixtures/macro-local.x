#include "x2c.x"

$(defun local-bias () 1)

static int fixture_select(int value) {
  return 1000 + value;
}

macro Expression $fixture_select(Expr $value) => (2000 + $value)

static int local_macros(int base) {
  int before = fixture_select(1);
  int first = 0, explicit_global = 0, explicit_call = 0;
  int call_site = 0, nested = 0, restored = 0, replaced = 0;
  int assigned = 0, assigned_again = 0, generated_value = 0;
  int generated_inline = 0, repeated = 0, field_value = 0, enum_value = 0;
  int entry_value = 0, decorated = 0;

  {
    int offset = 2;

    macro Expression fixture_select(Expr $value) => (
      base + offset + $value + $(local-bias)
    )

    macro Expression mixed(Expr $value) => (offset + $value)

    macro Statement assign(Expr $target, Expr $value) using $temporary => {
      int $temporary = base + $value;
      int generated = $temporary;
      $target = generated;
    }

    macro Statement define_generated() => {
      macro Expression generated(Expr $value) => (base + $value)
    }

    macro Statement define_and_use(Expr $target) => {
      macro Expression generated_here(Expr $value) => (base + $value)
      $target = generated_here(13);
    }

    macro Decorator repeat(Block $target) => {
      $target
      $target
    }

    macro Decorator nonzero(Expr $target) => ($target != 0)

    macro Field field() => {
      int $(x2c.ident "value");
    }

    macro Decorator keep_field(Field $target) => {
      $target
    }

    macro Enumerator states() => {
      $(x2c.ident "LOCAL_READY") = 3,
      $(x2c.ident "LOCAL_DONE")
    }

    macro Entry pair(Expr $key, Expr $value) => {
      $key: $value
    }

    first = fixture_select(3);
    explicit_global = $fixture_select(4);
    explicit_call = (fixture_select)(5);
    {
      int offset = 100;
      call_site = fixture_select(offset);

      macro Expression fixture_select(Expr $value) => (
        base + offset + $value
      )

      nested = fixture_select(6);
    }
    restored = fixture_select(7);

    macro Expression fixture_select(Expr $value) => (base + $value)

    replaced = fixture_select(9);
    assign(assigned, 8);
    assign(assigned_again, 9);
    define_generated();
    generated_value = generated(12);
    define_and_use(generated_inline);
    repeat repeated++;

    struct Local {
      field();
      keep_field int kept;
    } local = { .value = 7, .kept = 4 };
    enum LocalState {
      states()
    } state = LOCAL_DONE;
    Map entries = %{ ${pair("answer", 42)} };

    field_value = local.value;
    enum_value = state;
    entry_value = entries[%"answer"].int();
    decorated = nonzero local.kept;
  }

  int after = fixture_select(2);
  printf(
    "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
    before, first, explicit_global, explicit_call, call_site, nested,
    restored, replaced, assigned, assigned_again, generated_value,
    generated_inline, repeated, field_value, enum_value, entry_value,
    decorated, after
  );
  return before != 1001 || first != 16 || explicit_global != 2004 ||
         explicit_call != 1005 || call_site != 113 || nested != 116 ||
         restored != 20 || replaced != 19 || assigned != 18 ||
         assigned_again != 19 || generated_value != 22 ||
         generated_inline != 23 || repeated != 2 ||
         field_value != 7 || enum_value != 4 || entry_value != 42 ||
         decorated != 1 || after != 1002;
}

int main(void) {
  return local_macros(10);
}
