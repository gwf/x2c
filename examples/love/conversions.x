/* Show verified numeric and typed nonnumeric Var crossings. */


int main(void) {
  Var integer_value = 42;
  Var floating_value = 3.14;
  Var string_value = %"hello";
  Var list_value = %(alpha beta gamma);
  Var symbol_value = <config>;

  int integer_round_trip = integer_value;
  double integer_to_double = integer_value;
  double floating_round_trip = floating_value;
  String string_round_trip = string_value;
  List list_round_trip = list_value;
  Symbol symbol_round_trip = symbol_value;

  printf("integer: %d\n", integer_round_trip);
  printf("integer-to-double: %f\n", integer_to_double);
  printf("floating: %f\n", floating_round_trip);
  printf("string: %s\n", string_round_trip);
  printf("list-length: %d\n", list_round_trip.len());
  printf("symbol: %s\n", symbol_round_trip.str());

  List mixed = %(
    $integer_value
    $floating_value
    $string_value
    $symbol_value
    $list_value
  );
  foreach(Var item, mixed)
    printf("mixed: %s %s\n", item.tag().str(), item);

  return 0;
}
