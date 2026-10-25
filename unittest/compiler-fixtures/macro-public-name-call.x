#include "x2c.x"
#include "meta.x"

/* A `$x2c_ident` call gives a name the body declares its public spelling
   in declarator, parameter, tag, and typedef positions, and its references
   are typed where the expansion lands. */
macro Unit $first.public(Name $function) {
  int $function(int *$x2c_ident("values"), int $x2c_ident("count")) {
    if (!$x2c_ident("values"))
      raise %(bad-arg (operation $($Code.binding_spelling($function))));
    return $x2c_ident("values")[$x2c_ident("count") - 1];
  }
}

$first.public(last_of);

macro Unit $region.public() {
  typedef struct $x2c_ident("Region") {
    String label;
  } $x2c_ident("Region");

  int $x2c_ident("region_width")(Region $x2c_ident("region")) =>
    $x2c_ident("region").label.len();
}

$region.public();

int main(void) {
  int values[] = {3, 5, 8};
  Region region = {"sixteen"};
  printf("%d %d\n", last_of(values, 3), region_width(region));
  try {
    last_of(NULL, 0);
  }
  catch %(bad-arg (operation ?name)):
    printf("%s\n", (char *)(String) name);
  return 0;
}
