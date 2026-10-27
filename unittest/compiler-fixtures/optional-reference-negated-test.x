static int use(int &value) => value;

/* After a returning arm that the reference reaches when present, the
   reference is absent. */
static int after_negated(int &?value) {
  if (!(value == NULL)) return 0;
  return use(value);
}

int main(void) => after_negated(NULL);
