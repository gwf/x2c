
$(import "support/answer.xmacro")

int main(void) {
  printf("%d\n", $example.answer(40));
  return 0;
}
