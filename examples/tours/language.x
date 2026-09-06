/*  language.x -- executable fifteen-minute language tour */


int main(void) {
  Scope.retain();

  Var answer = 41;
  answer += 1;
  String language = %"x2c";
  printf("%s\n", %"dynamic=${answer.integer()} language=$language");

  List packet = %(build $answer fast);
  (Symbol action, long value, Symbol quality) = packet;
  printf("%s/%ld/%s\n", action.str(), value, quality.str());

  Array values = %[1, 2];
  values.push(3);
  Map facts = %{name: $language};
  facts[<values>] = values.len();
  printf("values=%ld name=%s\n",
         facts[<values>].integer(), facts[<name>].string());

  File input = tmpfile();
  input.puts("alpha beta\nbeta gamma\n");
  input.rewind();
  Map counts = %{};
  foreach(String line, input) {
    List words = line.strip(" \n").split(%" ");
    foreach(String word, words) {
      Var old;
      long count = counts.try_get(word, &old) ? old.integer() : 0;
      counts[word] = count + 1;
    }
  }
  printf("beta=%ld\n", counts[%"beta"].integer());
  input.close();

  List numbers = %(1 2 3 4), doubled = numbers.map(%!(item) => item * 2);
  printf("doubled=%s\n", doubled.repr());

  match (packet) {
    case %(build ?amount fast): printf("match=ready %ld\n", amount.integer());
  }

  Lisp lisp = Lisp.new();
  Var form = lisp.eval_string("'(x2c has lisp)");
  printf("lisp=%s\n", form.repr());
  lisp.destroy();

  Scope.release();
  return 0;
}
