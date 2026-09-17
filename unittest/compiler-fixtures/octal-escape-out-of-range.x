int main(void) {
  String text = %"a\400b";
  return text.len();
}
