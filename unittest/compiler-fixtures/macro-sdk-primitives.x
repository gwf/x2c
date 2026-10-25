#include "x2c.x"

static int sdk_existing(void) {
  return 40;
}

static int sdk_sum(int left, int right) {
  return left + right;
}

meta static String repr_of(List value) => value.repr();

meta static String joined(String first, String second, String third) =>
  first + second + third;

macro Unit $sdk_functions(Expr $value) {
  static $Code.type($value)
  $x2c_ident("sdk_exact")(void) {
    return $value;
  }

  static int private(void) {
    return 0;
  }

  static char *$x2c_ident("sdk_rendered")(void) {
    return $repr_of($value);
  }

  static char *$x2c_ident("sdk_composed")(void) {
    return $joined("macro", "-", "sdk");
  }

  static String $x2c_ident("sdk_literal")(void) {
    return $joined("runtime", "-", "string");
  }
}

macro Expression $call_existing() => $x2c_ident("sdk_existing")();

macro Stmt $print_value(Expr $value) {
  printf("%d\n", $value);
}

macro Unit $project_parameters(Name $name, Param @parameters) {
  static int $name(@parameters) {
    return sdk_sum(
      @Code.arguments($parameters)
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
