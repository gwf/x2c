int main(void) {
  String text = %"implicit";
  printf("%s\n", text);
  return text.len() != 8;
}
