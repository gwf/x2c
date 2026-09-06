
macro Decorator $trace(Function $function, Expr $label) => {
  printf(
    "[%s] enter %s\n",
    $label,
    $(x2c.literal.string (x2c.function.name $function))
  );
  defer printf("[%s] leave\n", $label);
  $(x2c.function.body $function)...
}

macro Decorator $require_parameter(Function $function, Name $parameter) => {
  if (!$(x2c.function.parameter $function $parameter)) return -1;
  $(x2c.function.body $function)...
}

macro Decorator $increment(Expr $target) => ($target + 1)

$trace("request")
$require_parameter(value)
int answer(int value) {
  return value * 2;
}

int main(void) {
  printf("%d\n", $increment() answer(21));
  return 0;
}
