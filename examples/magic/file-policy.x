/*  runtime.x -- A small policy language inside an ordinary x2c program. */

$lisp.binding(policy, "role-limit")
static int role_limit(String role) {
  if (role == %"admin") return 100;
  if (role == %"editor") return 8;
  return 2;
}

$lisp.binding(policy, "clamp")
static int clamp(int value, int low, int high) {
  if (value < low) return low;
  if (value > high) return high;
  return value;
}

int main(int argc, char **argv) {
  if (argc != 2) {
    Stderr.puts("usage: file-policy POLICY.xlisp\n");
    return 2;
  }

  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  $lisp.install(lisp, policy);

  File program = File.open(argv[1], "r");
  defer program.close();
  Lisp.eval_file(lisp, program);

  String role = "editor";
  int requested = 14;
  List outcome = lisp.eval(%(
    decide (quote ((role $role) (requested $requested)))
  ));

  (String decision, int allowed) = outcome;
  printf("%s: %d\n", decision, allowed);
  return 0;
}
