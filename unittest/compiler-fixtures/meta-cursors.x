/* Frame-slot cursor walks preserve collection reads and loop exits. */
#include "x2c.x"

/* A Map from alternating keys and values. */
$(defun cursor_map (flat)
  (if (null? flat) (Map.new)
    (let ((map (cursor_map (cddr flat))))
      (begin (Map.setindex map (car flat) (cadr flat)) map))))

$(import "meta-cursors.xmacro")

int main(void) {
  Array values = [1, 2, 3, 4, 5], empty = [];
  Map weights = {1: 2, 3: 4};
  Array changing = [1, 2];
  printf("array %d %d\n", $(cursor_array (List.array '(1 2 3 4 5))),
         cursor_array(values));
  printf("empty %d %d\n", $(cursor_array (List.array '())),
         cursor_array(empty));
  printf("nested %d %d\n",
         $(cursor_nested (List.array '(1 2 3 4 5)) (cursor_map '(1 2 3 4))),
         cursor_nested(values, weights));
  printf("mutate %d %d\n", $(cursor_mutate (List.array '(1 2))),
         cursor_mutate(changing));
  printf("snapshot %d\n", $(cursor_snapshot (cursor_map '(1 2 3 4))));
  printf("after-array %d %d\n",
         $(cursor_after_array (List.array '(1 2 3 4 5))),
         cursor_after_array(values));
  printf("after-map %d\n", $(cursor_after_map (cursor_map '(1 2 3 2))));
  printf("after-list %d %d\n", $(cursor_after_list '(1 2 3)),
         cursor_after_list(%(1 2 3)));
  printf("address %d %d\n", $(cursor_address (List.array '(1 2 3 4 5))),
         cursor_address(values));
  values.free();
  empty.free();
  weights.cleanup();
  changing.free();
  return 0;
}
