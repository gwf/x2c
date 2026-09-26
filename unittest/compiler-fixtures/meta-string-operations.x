/* String operations reuse native byte and canonical-value semantics. */
#include "x2c.x"
meta int text_contains_digit(int unused) {
  (void) unused;
  String empty = "";
  return "a1".contains_digit()
    && !"abc".contains_digit()
    && !empty.contains_digit();
}
meta int text_is_alpha(int unused) {
  (void) unused;
  String empty = "";
  return "Ab".is_alpha() && !"a1".is_alpha() && !empty.is_alpha();
}
meta int text_is_alpha_under(int unused) {
  (void) unused;
  String empty = "";
  return "a_B".is_alpha_under()
    && !"a1".is_alpha_under()
    && !empty.is_alpha_under();
}
meta int text_is_digit(int unused) {
  (void) unused;
  String empty = "";
  return "123".is_digit() && !"12a".is_digit() && !empty.is_digit();
}
meta int text_is_alnum(int unused) {
  (void) unused;
  String empty = "";
  return "a1B".is_alnum() && !"a_".is_alnum() && !empty.is_alnum();
}
meta int text_is_alnum_under(int unused) {
  (void) unused;
  String empty = "";
  return "a_1".is_alnum_under()
    && !"a-".is_alnum_under()
    && !empty.is_alnum_under();
}
meta int text_is_identifier(int unused) {
  (void) unused;
  String empty = "";
  return "_a1".is_identifier()
    && !"1a".is_identifier()
    && !empty.is_identifier();
}
meta int text_is_space(int unused) {
  (void) unused;
  String empty = "";
  return " \t".is_space() && !" a".is_space() && !empty.is_space();
}
meta int text_is_lower(int unused) {
  (void) unused;
  String empty = "";
  return "abc".is_lower() && !"Ab".is_lower() && !empty.is_lower();
}
meta int text_is_lower_under(int unused) {
  (void) unused;
  String empty = "";
  return "a_b".is_lower_under()
    && !"a_B".is_lower_under()
    && !empty.is_lower_under();
}
meta int text_is_upper(int unused) {
  (void) unused;
  String empty = "";
  return "ABC".is_upper() && !"aB".is_upper() && !empty.is_upper();
}
meta int text_is_upper_under(int unused) {
  (void) unused;
  String empty = "";
  return "A_B".is_upper_under()
    && !"a_B".is_upper_under()
    && !empty.is_upper_under();
}
meta int text_compare(int unused) {
  (void) unused;
  return "abc".compare("abd") < 0 && "abc".compare("abc") == 0;
}
meta int text_hash(int unused) {
  (void) unused;
  return "abc".hash() != 0;
}
meta int text_symbol(int unused) {
  (void) unused;
  return "alpha".symbol() == <alpha>;
}
meta int text_dedent(int unused) {
  (void) unused;
  return "\n  a\n    b\n  ".dedent().equal("a\n  b\n");
}
meta int text_keep(int unused) {
  (void) unused;
  return "abacad".keep("ac").equal("aaca") && "x".keep("").len() == 0;
}
meta int text_reject(int unused) {
  (void) unused;
  return "abacad".reject("ac").equal("bd") && "x".reject("").equal("x");
}
meta int text_squeeze(int unused) {
  (void) unused;
  return "aaabbbccc".squeeze("ac").equal("abbbc")
    && "aa".squeeze("").equal("aa");
}
meta int text_pad_left(int unused) {
  (void) unused;
  return "x".pad_left(3, '.').equal("..x")
    && "abc".pad_left(1, '.').equal("abc");
}
meta int text_pad_right(int unused) {
  (void) unused;
  return "x".pad_right(3, '.').equal("x..");
}
meta int text_pad_center(int unused) {
  (void) unused;
  return "x".pad_center(4, '.').equal(".x..");
}
meta int text_new_fill(int unused) {
  (void) unused;
  return String.new_fill('x', 3).equal("xxx")
    && String.new_fill('x', -1).len() == 0;
}
meta int text_find_within(int unused) {
  (void) unused;
  return "abcabc".find_within("c", -4, -1) == 2
    && "abc".find_within("x", 0, -1) == -1;
}
meta int text_replace_n(int unused) {
  (void) unused;
  return "aaaa".replace_n("a", "b", 2).equal("bbaa")
    && "aa".replace_n("a", "b", 0).equal("aa");
}
meta int text_split_n(int unused) {
  (void) unused;
  return "a:b:c".split_n(":", 1).equal(%("a" "b:c"))
    && "a:b".split_n(":", 0).equal(%("a:b"));
}
meta int text_lstrip(int unused) {
  (void) unused;
  return "  a  ".lstrip((char *) 0).equal("a  ")
    && "xxax".lstrip("x").equal("ax")
    && " ".lstrip(" ").len() == 0;
}
meta int text_rstrip(int unused) {
  (void) unused;
  return "  a  ".rstrip((char *) 0).equal("  a")
    && "xaxx".rstrip("x").equal("xa")
    && " ".rstrip(" ").len() == 0;
}
meta String text_plain(String text) {
  String t = "${text}abc";
  return t;
}
meta String text_numbers(int x, int y) {
  String t = %"${x} and ${y}";
  return t;
}
meta String text_expressions(String who) {
  return %"hi $who, ${who.upper()} ${who.len() + 1}";
}
meta String text_nested(String who) {
  String e = "";
  return %"[${e}]${%"<$who>"}$e";
}
meta String text_empty(int unused) {
  (void) unused;
  return %"";
}
meta String text_scalars(char c, unsigned char uc, short h,
                         unsigned short uh, unsigned u) {
  return %"$c $uc $h $uh $u";
}
meta String text_wide_scalars(unsigned long ul, long long ll,
                              unsigned long long ull) {
  return %"$ul $ll $ull";
}
meta String text_floats(float f, long double ld) {
  return %"$f $ld";
}
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
