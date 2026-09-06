int main(void) {
  List list = %(alpha 1 "beta");
  Array array = %[alpha 1 "beta"];
  Map map = %{alpha: 1, beta: 2};
  String text = %"left${1 + 2}right";
  Symbol symbol = <token-name>;
  int modulo = 7 % 3;
  return modulo;
}
