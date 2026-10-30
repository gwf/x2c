#include "x2c.x"

int identity(int n) { return n; }
alias try to identity;
alias raise to identity;

macro Unit $answer(Name $name) { int $name(void) { return 7; } }
keyword protocol $answer;
protocol(answer);

macro Field $field() { int value; }
keyword delegate $field;
struct Generated { delegate(); };

macro Decorator $once(Stmt $body) { $body }
keyword delegate $once;
struct Wrapped { delegate String value; };
keyword protocol $once;
protocol Context(T) { int T.value(T); }

int main(void) {
  int total = try(4) + raise(5) + answer();
  {
    int try = 2;
    total += try;
  }
  {
    alias catch to identity;
    total += catch(3);
  }
  struct Generated generated = { 4 };
  total += generated.value;
  {
    int macro_calls = 0;
    macro Stmt finally() { macro_calls++; }
    macro Stmt catch() { macro_calls++; }
    try { total++; }
    catch: { return 1; }
    finally();
    catch();
    if (macro_calls != 2) return 2;
  }
  printf("aliases %d\n", total);
  return total != 26;
}
