#pragma once

meta int imported_segment_value(int offset) => 37 + offset;

macro Unit $project.imports.segment(Name $function) {
  int $function(void) {
    return $imported_segment_value(5);
  }
}
