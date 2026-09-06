#include "x2c.x"

typedef Block MacroArrayInt;
typedef List MacroRow;

Var MacroArrayInt.var(MacroArrayInt);
MacroArrayInt Var.macroarrayint(Var);
MacroArrayInt MacroArrayInt.new(void);
int MacroArrayInt.equal(MacroArrayInt, MacroArrayInt);
int MacroArrayInt.contains(MacroArrayInt, int);
int MacroArrayInt.getindex(MacroArrayInt, int);

static inline Var MacroRow.var(MacroRow value) {
  return Var.new(<list>, value);
}

static inline MacroRow Var.macrorow(Var value) {
  return value.list();
}

macro Unit $generated.array(
  Type $array, Type $element, Name $unbox, Literal $tag
) => {
  inline Var $array.var($array array) {
    return Var.new($tag, array);
  }

  inline $array Var.$unbox(Var value) {
    return ($array) value.pointer();
  }

  $array $array.new(void) {
    return Block.new(sizeof($element));
  }

  int $array.equal($array a, $array b) {
    return (void *) a == (void *) b;
  }

  int $array.contains($array array, $element needle) {
    $element *data = ($element *) array.bytes;
    for (size_t i = 0; i < array.length; i++)
      if (data[i] == needle) return 1;
    return 0;
  }

  $element $array.getindex($array array, int index) {
    return (($element *) array.bytes)[index];
  }

  protocol Var($array) tag $tag;
}

macro Unit $generated.representation(
  Type $base, Type $participant, Type $representation
) => {
  protocol $base($participant) as $representation;
}

$generated.array(
  MacroArrayInt, int, macroarrayint, <macarray>
);
$generated.representation(Var, MacroRow, List);

int main(void) {
  MacroArrayInt array = MacroArrayInt.new();
  array.append(&(int) { 31 }, 1);
  MacroRow row = %(represented);
  Var boxed_array = array, boxed_row = row;
  printf("%d %d %d %d %d %d\n", array.equal(array),
         array.contains(31), array.getindex(0), boxed_row is MacroRow,
         boxed_array is MacroArrayInt, boxed_array[0].int());
  array.free();
  return 0;
}
