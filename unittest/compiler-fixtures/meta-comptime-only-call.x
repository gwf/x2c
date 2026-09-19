/*  meta-comptime-only-call.x -- calling a compile-time-only meta function

    A `meta` function that reaches a `Meta` operation exists only inside a
    compiler, so no unit emits a definition for it. A run-time call to one
    used to reach the linker as an undefined symbol naming the C spelling;
    it is refused at the call instead. `mc_wrap` is the contrast: calling
    such a function is what makes the caller compile-time only too, so a
    `meta` body is left alone. See `plans/meta-functions.md`.
*/

#include "x2c.x"
#include "meta.x"

meta static List mc_name(String text) => Meta.literal_string(text);

meta static List mc_wrap(String text) => mc_name(text);

int main(void) {
  List node = mc_name("hi");
  return node.len();
}
