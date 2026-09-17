/*  language.x -- executable fifteen-minute language tour */


int main(void) {
  $scope() {
    Var answer = 41;
    answer += 1;
    String language = "x2c";
    printf("%s\n", %"dynamic=$answer language=$language");

    List packet = %(build $answer fast);
    (Symbol action, long value, Symbol quality) = packet;
    printf("%s/%ld/%s\n", action.str(), value, quality.str());

    Array values = [1, 2];
    values.push(3);
    Map facts = {name: language};
    facts[<values>] = values.len();
    printf("values=%ld name=%s\n",
           facts[<values>].integer(), facts[<name>].string());

    File input = $auto(tmpfile());
    input.puts("alpha beta\nbeta gamma\n");
    input.rewind();
    Map counts = {};
    foreach(String line, input)
      foreach(String word, line.strip(" \n").split(" "))
        counts[word] = counts.getdefault(word, 0).integer() + 1;
    printf("beta=%ld\n", counts["beta"].integer());

    List numbers = %(1 2 3 4), doubled = numbers.map(%!(item) => item * 2);
    printf("doubled=%s\n", doubled.repr());

    match (packet) {
      case %(build ?amount fast): printf("match=ready %ld\n", amount.integer());
    }

    Lisp lisp = $auto(Lisp.new());
    printf("lisp=%s\n", lisp.eval_string("'(x2c has lisp)").repr());
  }
  return 0;
}
