/* String operations reuse native byte and canonical-value semantics. */
#include "x2c.x"
$(import "meta-string-operations.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $text_contains_digit(0), text_contains_digit(argc - 1));
  printf("%d %d\n", $text_is_alpha(0), text_is_alpha(argc - 1));
  printf("%d %d\n", $text_is_alpha_under(0), text_is_alpha_under(argc - 1));
  printf("%d %d\n", $text_is_digit(0), text_is_digit(argc - 1));
  printf("%d %d\n", $text_is_alnum(0), text_is_alnum(argc - 1));
  printf("%d %d\n", $text_is_alnum_under(0), text_is_alnum_under(argc - 1));
  printf("%d %d\n", $text_is_identifier(0), text_is_identifier(argc - 1));
  printf("%d %d\n", $text_is_space(0), text_is_space(argc - 1));
  printf("%d %d\n", $text_is_lower(0), text_is_lower(argc - 1));
  printf("%d %d\n", $text_is_lower_under(0), text_is_lower_under(argc - 1));
  printf("%d %d\n", $text_is_upper(0), text_is_upper(argc - 1));
  printf("%d %d\n", $text_is_upper_under(0), text_is_upper_under(argc - 1));
  printf("%d %d\n", $text_compare(0), text_compare(argc - 1));
  printf("%d %d\n", $text_hash(0), text_hash(argc - 1));
  printf("%d %d\n", $text_symbol(0), text_symbol(argc - 1));
  printf("%d %d\n", $text_dedent(0), text_dedent(argc - 1));
  printf("%d %d\n", $text_keep(0), text_keep(argc - 1));
  printf("%d %d\n", $text_reject(0), text_reject(argc - 1));
  printf("%d %d\n", $text_squeeze(0), text_squeeze(argc - 1));
  printf("%d %d\n", $text_pad_left(0), text_pad_left(argc - 1));
  printf("%d %d\n", $text_pad_right(0), text_pad_right(argc - 1));
  printf("%d %d\n", $text_pad_center(0), text_pad_center(argc - 1));
  printf("%d %d\n", $text_new_fill(0), text_new_fill(argc - 1));
  printf("%d %d\n", $text_find_within(0), text_find_within(argc - 1));
  printf("%d %d\n", $text_replace_n(0), text_replace_n(argc - 1));
  printf("%d %d\n", $text_split_n(0), text_split_n(argc - 1));
  printf("%d %d\n", $text_lstrip(0), text_lstrip(argc - 1));
  printf("%d %d\n", $text_rstrip(0), text_rstrip(argc - 1));
  printf("[%s] [%s]\n", $text_plain("q"), text_plain("q"));
  printf("[%s] [%s]\n", $text_numbers(1, 2), text_numbers(1, argc + 1));
  printf("[%s] [%s]\n", $text_expressions("ab"), text_expressions("ab"));
  printf("[%s] [%s]\n", $text_nested("ab"), text_nested("ab"));
  printf("%d %d\n", $text_empty(0).len(), text_empty(argc - 1).len());
  printf("[%s] [%s]\n", $text_scalars('x', 'y', -3, 4, 5),
    text_scalars('x', 'y', -3, 4, argc + 4));
  printf("[%s] [%s]\n", $text_wide_scalars(6, -7, 8),
    text_wide_scalars(6, -7, argc + 7));
  printf("[%s] [%s]\n", $text_floats(1.5, 2.5),
    text_floats(1.5, argc + 1.5));
  return 0;
}
