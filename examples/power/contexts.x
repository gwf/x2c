/*  contexts.x -- discard temporary work and export one result */

#include <stdio.h>

int main(void) {
  Context input = Context.open_isolated_named("input file");

  String temporary = String.new("temporary text");
  Array values = %[];
  values.push(temporary);
  values.push(42);

  Map result = %{};
  result[<values>] = values;
  result[<self>] = result;

  result = input.export(result);
  input.close();

  printf("text: %s\n", result[<values>].array()[0].string());
  printf("number: %ld\n", result[<values>].array()[1].integer());
  printf("cycle preserved: %s\n",
         result[<self>].map() == result ? "yes" : "no");
  return 0;
}
