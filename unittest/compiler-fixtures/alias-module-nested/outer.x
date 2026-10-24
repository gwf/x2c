static alias 1 as mine;
module int before_value(void) { return mine; }

module {
  "inner.x",
}

module int after_value(void) { return mine; }
