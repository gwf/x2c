static alias 1 as mine;

alias 2 as mine {
  module int first_value(void) { return mine; }
  alias 3 as mine {
    module int inner_value(void) { return mine; }
  }
  module int last_value(void) { return mine; }
  typedef struct Width { int values[mine]; } Width;
  module int field_count(void) {
    return sizeof(Width) / sizeof(int);
  }
}

module int outer_value(void) { return mine; }
