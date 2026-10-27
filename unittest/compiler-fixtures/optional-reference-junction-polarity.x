static int use(int &value) => value;

/* A false `||` requires each operand to be false, but `ready && !value` is
   false whenever `ready` is, so it does not prove `value` present. */
static int fallback(int ready, int &?value) =>
  (ready && !value) || use(value);

int main(void) => fallback(0, NULL);
