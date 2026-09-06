/* Provider for imported macro-generated protocol adoptions. */

#pragma once
#include "x2c.x"

typedef Block ExportOne;
typedef Block ExportTwo;

macro Unit $export.array(Type $array, Name $unbox, Literal $tag) => {
  Var $array.var($array);
  $array Var.$unbox(Var);
  int $array.equal($array, $array);
  int $array.contains($array, int);
  int $array.getindex($array, int);
  int $array.setindex($array, int, int);

  inline Var $array.var($array array) {
    return Var.new($tag, array);
  }

  inline $array Var.$unbox(Var value) {
    return ($array) value.pointer();
  }

  int $array.equal($array a, $array b) {
    return (void *) a == (void *) b;
  }

  int $array.contains($array array, int value) {
    return array.length == (size_t) value;
  }

  int $array.getindex($array array, int index) {
    return ((int *) array.bytes)[index];
  }

  int $array.setindex($array array, int index, int value) {
    ((int *) array.bytes)[index] = value;
    return value;
  }

  protocol Var($array);
}

$export.array(ExportOne, exportone, <exportone>);
$export.array(ExportTwo, exporttwo, <exporttwo>);
