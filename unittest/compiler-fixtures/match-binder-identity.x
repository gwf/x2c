#include "x2c.x"

static Var shadow = 100;

macro Stmt $match_private(Expr $caller, Expr $result) {
  match (%(5)) {
    case %(?shadow) if ($caller == 77):
      $result = shadow == 5 && $caller == 77;
    default: $result = 0;
  }
}

macro Stmt $catch_private(Expr $caller, Expr $result) {
  try raise %(probe (value 5));
  catch %(probe (value ?shadow)):
    $result = shadow == 5 && $caller == 77;
}

macro Unit $match_function(Name $name) {
  static int $name(void) {
    Func reader = NULL;
    match (%(entry 5)) {
      case %(entry ?shadow): reader = %!() => shadow;
    }
    return reader().int();
  }
}

$match_function(template_reader);

int main(void) {
  auto {
    Func snapshot = NULL, shared = NULL;
    match (%(entry 5)) {
      case %(entry ?shadow): {
        snapshot = %!() => shadow;
        shared = %!() using &shadow => shadow += 1;
        if (shared() != 6 || shadow != 6) return 1;
      }
    }
    if (snapshot() != 5 || shared() != 7 || shadow != 100) return 2;
    Var caller = 77;
    int matched = 0, caught = 0;
    $match_private(caller, matched);
    $catch_private(caller, caught);
    if (!matched || !caught || caller != 77) return 3;
    if (template_reader() != 5) return 4;
    Func tail_reader = NULL;
    match (%(same 5 5 extra)) {
      case %(same ?value ?value *rest): {
        if (value != 5) return 5;
        tail_reader = %!() => rest;
      }
    }
    if (tail_reader().list().len() != 1) return 6;
    puts("binding identities preserved");
  }
  return 0;
}
