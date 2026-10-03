#include "x2c.x"
$(import "macro-import-literal-cache.xmacro")
$(import "macro-import-literal-cache.xmacro")

int main(void) {
  List other = %("untouched");
  $imported_literal(first);
  $imported_literal(second);
  List direct = %("abc" "de");
  List nested = $imported_nested_literal();
  String text = $imported_string_literal();
  printf("%s %s %s %s\n", first.repr().str(), other.repr().str(),
    nested.repr().str(), text.str());
  return first != second || first != direct || nested.car().list() != first;
}
