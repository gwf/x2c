#include "x2c.x"
macro Expression $ordinary.value() => 5;
keyword before_value $ordinary.value;
#include "ordinary-interface-provider.x"

int main(void) {
  List other = %("untouched");
  $ordinary.literal(first);
  $ordinary.literal(second);
  List direct = %("abc" "de");
  List nested = $ordinary.nested_literal();
  String text = $ordinary.string();
  printf("%d %d %d %d %d %d %d %s %s %s %s\n", before_value(), first_value(),
    $ordinary.value(), $ordinary.nested(), $ordinary.generated_first(),
    $ordinary.generated_second(), $(ordinary.public_value),
    first.repr().str(), other.repr().str(),
    nested.repr().str(), text.str());
  return (void *) first != (void *) second ||
         (void *) first != (void *) direct ||
         (void *) nested.car().list() != (void *) first;
}
