#include "x2c.x"

static int sdk_existing(void) {
  return 40;
}

static int sdk_sum(int left, int right) {
  return left + right;
}

macro Unit $sdk_functions(Expr $value) using $private => {
  static $(x2c.syntax.type $value)
  $(x2c.ident "sdk_exact")(void) {
    return $value;
  }

  static int $private(void) {
    return 0;
  }

  static char *$(x2c.ident "sdk_rendered")(void) {
    return $(repr $value);
  }

  static char *$(x2c.ident "sdk_composed")(void) {
    return $(string-append "macro" "-" "sdk");
  }

  static String $(x2c.ident "sdk_literal")(void) {
    return $(x2c.literal.string(
      string-append "runtime" "-" "string"
    ));
  }
}

macro Expression $call_existing() => ($(x2c.ident "sdk_existing")())

macro Statement $print_value(Expr $value) => {
  printf("%d\n", $value);
}

macro Unit $project_parameters(Name $name, Param $parameters...) => {
  static int $name($parameters...) {
    return sdk_sum(
      $(x2c.parameters.arguments $parameters)...
    );
  }
}

$sdk_functions(42);
$project_parameters(sdk_projected, int left, int right);
int main(void) {
  int native = 7;
  $print_value(sdk_exact());
  printf("%d %d %s %s %d\n",
         $call_existing(),
         sdk_rendered()[0] != 0,
         sdk_composed(),
         sdk_literal(),
         sdk_projected(19, 23));
  printf("%d %d\n", native, 1);
  return 0;
}
