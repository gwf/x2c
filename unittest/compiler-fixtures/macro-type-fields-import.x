#pragma once

macro Unit $imported_record(name $tag) {
  struct $tag {
    short $x2c_ident("included");
  };
}
