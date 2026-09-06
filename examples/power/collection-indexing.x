#include <stdio.h>
#include "typed-array.x"


int main(void) {
  // Native pointer and array indexing (baseline C semantics).
  int raw[4] = { 1, 2, 3, 4 };
  int raw_first = raw[0];
  int *ptr = raw;
  int ptr_second = ptr[1];
  raw[2] = 30;
  ptr[3] = raw_first + ptr_second;

  // Built-in Array indexing and explicit helper calls (Var-typed elements).
  Array arr = %[10, 20, 30, 40, 50];
  Var arr_zero = arr[0];              // RHS get-index
  Var arr_neg = arr[-1];              // RHS negative index
  Var arr_call = arr.getindex(2);     // Explicit method call
  arr[1] = 200;                       // LHS set-index
  arr[-2] = 300;                      // Negative LHS set-index
  arr.setindex(4, 500);               // Explicit set-index helper

  // Packed Array brackets are raw native indexing; try_get is checked.
  ArrayInt packed = ArrayInt.new();
  packed.push(10);
  packed.push(20);
  packed[1] += 5;
  int checked = -1;
  int last_ok = packed.try_get(-1, &checked);
  int missing = packed.try_get(99, &checked);

  // List and String indexing (read paths via brackets or helpers).
  List words = %("alpha" "beta" "gamma");
  Var second_word = words[1];
  Var last_word = words[-1];
  Var words_call = words.getindex(0);

  String text = "sphinx of black quartz";
  int first_char = text[0];
  int last_char = text[-1];
  int third_char = text.getindex(2);

  // Slice expressions with optional start / stop / step pieces.
  Array slice_all = arr[:];
  Array slice_prefix = arr[:3];
  Array slice_suffix = arr[2:];
  Array slice_middle = arr[1:4];
  Array slice_stride = arr[0:5:2];
  Array slice_backwards = arr[4:0:-1];
  Array slice_full_rev = arr[::-1];
  Array slice_implicit_step = arr[1:4:];
  Array slice_implicit_bounds = arr[::2];

  String text_all = text[:];
  String text_prefix = text[:6];
  String text_suffix = text[7:];
  String text_stride = text[::3];
  String text_reverse = text[::-1];

  printf("raw: [%d %d %d %d] ptr[1]=%d\n",
         raw[0], raw[1], raw[2], raw[3], ptr_second);
  printf("arr get: %d %d call=%d\n",
         arr_zero.int(), arr_neg.int(), arr_call.int());
  printf("arr after setindex: %s\n", arr.repr());
  printf("packed: second=%d last-ok=%d checked=%d missing=%d\n",
         packed[1], last_ok, checked, missing);
  printf("words: second=%s last=%s call=%s\n",
         second_word, last_word, words_call);
  printf("text chars: first=%c last=%c third=%c\n",
         first_char, last_char, third_char);
  printf("slices: all=%s prefix=%s suffix=%s middle=%s stride=%s back=%s\n",
         slice_all.repr(), slice_prefix.repr(),
         slice_suffix.repr(), slice_middle.repr(),
         slice_stride.repr(), slice_backwards.repr());
  printf("slices (implicit): step=%s bounds=%s full_rev=%s\n",
         slice_implicit_step.repr(), slice_implicit_bounds.repr(),
         slice_full_rev.repr());
  printf("text slices: all=%s prefix=%s suffix=%s stride=%s reverse=%s\n",
         text_all.repr(), text_prefix.repr(), text_suffix.repr(),
         text_stride.repr(), text_reverse.repr());
  return 0;
}
