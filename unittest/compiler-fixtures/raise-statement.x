#include "x2c.x"

static void raise_empty(void) {
  raise %(raise-prob);
}

static List observed;

static Symbol observe_newest(List errors, Var data) {
  (void) data;
  observed = Error.snapshot(errors.last());
  return <handled>;
}

int main(void) {
  Error.initialize();
  ErrorHandler observer = Error.push(observe_newest, void);
  int bytes = 64;
  raise %(collected (bytes $bytes) (owner "raise-probe"));
  List entry = observed;
  List detail = entry.assoc(<detail>);
  List location = entry.assoc(<location>);
  raise_empty();
  List empty_entry = observed;
  List empty_detail = empty_entry.assoc(<detail>);
  List empty_location = empty_entry.assoc(<location>);
  Error.pop(observer);
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
