/*  Calls into region-holder.x from a region this unit opens. Only the
    calls that outlive the region report.
*/

#include "region-holder.x"

void region_user_static(void) {
  $scope() {
    Array scratch = [];
    region_keep(scratch);
  }
}

void region_user_parameter(Array outer) {
  $scope() {
    Array scratch = [];
    region_borrow(outer, scratch);
  }
}

void region_user_same_region(void) {
  $scope() {
    Array scratch = [];
    region_borrow(scratch, 1);
  }
}
