#include "x2c.x"

static void raise_empty(void) {
  raise %(raise-prob);
}

int main(void) {
  Error.initialize();
  Error.policy_set(<collected>, <collect>);
  Error.policy_set(<raise-prob>, <collect>);
  int bytes = 64, mark = Error.mark();
  raise %(collected (bytes $bytes) (owner "raise-probe"));
  List entry = Error.since(mark).car();
  List detail = entry.assoc(<detail>);
  List location = entry.assoc(<location>);
  int empty_mark = Error.mark();
  raise_empty();
  List empty_entry = Error.since(empty_mark).car();
  List empty_detail = empty_entry.assoc(<detail>);
  List empty_location = empty_entry.assoc(<location>);
  printf("%s %ld %s %s:%ld:%s %ld:%s\n",
         entry.assoc(<code>).symbol().str(),
         detail[0].list().cadr().integer(),
         detail[1].list().cadr().string(),
         location.assoc(<file>).string(),
         location.assoc(<line>).integer(),
         location.assoc(<function>).string(),
         empty_detail.len(),
         empty_location.assoc(<function>).string());
  return 0;
}

static void raise_terminal(void) {
  raise %(bad-arg);
}

static void raise_after_return(int code) {
  if (!code) return;
  raise %(bad-arg);
}

static void raise_caught(void) {
  try {
    raise %(bad-arg);
  }
  catch %(bad-arg): {}
}
