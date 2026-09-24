#include "x2c.x"

/* Both prototypes are accepted without a runtime row: a returned handle is
   a fresh allocation in the active Scope, and a handle argument with a
   scalar result is borrowed for the call. Returning the fresh allocation
   out of the `$scope` that holds it is an error. */

typedef struct Widget *Widget;

meta Widget widget_new(int size);
meta int widget_size(Widget widget);

meta Widget leak(void) {
  $scope() { return widget_new(3); }
}

int main(void) { return 0; }
