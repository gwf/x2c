#pragma once

#include "meta.x"

// The package type is declared by the unit that includes this file.
meta List quoted_reader(String name) {
  List function = x2c_ident(name);
  List field = x2c_ident("field");
  List unit = $!Unit{
    inline size_t $function(Field $field) => field_capacity($field);
  };
  return $(unit);
}

macro Unit $quoted.reader(Literal $name) { @quoted_reader($name) }
