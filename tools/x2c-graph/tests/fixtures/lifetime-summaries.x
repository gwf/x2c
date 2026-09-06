char *summary_public(void);
char *summary_ambiguous(void);
char *summary_missing(void);

static char *_summary_direct(void) {
  return Scope.memdup("direct", 7);
}

static char *_summary_transitive(void) {
  return _summary_direct();
}

static char *_summary_static(void) {
  return Scope.memdup("static", 7);
}

static char *_summary_recursive_seed(int base) {
  if (base) return Scope.memdup("recursive", 10);
  return _summary_recursive_seed(1);
}

static char *_summary_recursive(void) {
  return _summary_recursive();
}

static char *_summary_indirect(char *(*callback)(void)) {
  return callback();
}

static char *_summary_mixed(int allocate) {
  if (allocate) return Scope.memdup("mixed", 6);
  return NULL;
}

static List _summary_converted(void) {
  Array values = %[];
  List result = values;
  return result;
}

static char *summary_direct_escape(void) {
  Scope.retain();
  char *result = _summary_direct();
  Scope.release();
  return result;
}

static char *summary_transitive_escape(void) {
  Scope.retain();
  char *result = _summary_transitive();
  Scope.release();
  return result;
}

static char *summary_static_escape(void) {
  Scope.retain();
  char *result = _summary_static();
  Scope.release();
  return result;
}

static char *summary_recursive_seed_escape(void) {
  Scope.retain();
  char *result = _summary_recursive_seed(0);
  Scope.release();
  return result;
}

static char *summary_public_escape(void) {
  Scope.retain();
  char *result = summary_public();
  Scope.release();
  return result;
}

static char *summary_recursive_unknown(void) {
  Scope.retain();
  char *result = _summary_recursive();
  Scope.release();
  return result;
}

static char *summary_indirect_unknown(char *(*callback)(void)) {
  Scope.retain();
  char *result = _summary_indirect(callback);
  Scope.release();
  return result;
}

static char *summary_mixed_unknown(void) {
  Scope.retain();
  char *result = _summary_mixed(1);
  Scope.release();
  return result;
}

static List summary_conversion_unknown(void) {
  Context work = Context.open_isolated_named("conversion");
  List result = _summary_converted();
  work.close();
  return result;
}

static char *summary_ambiguous_unknown(void) {
  Scope.retain();
  char *result = summary_ambiguous();
  Scope.release();
  return result;
}

static char *summary_missing_unknown(void) {
  Scope.retain();
  char *result = summary_missing();
  Scope.release();
  return result;
}

static String _summary_pooled(void) {
  return String.new("pooled");
}

static List _summary_list_free(void) {
  Array values = %[];
  values.push(1);
  return values.list_free();
}

static String summary_pooled_escape(void) {
  Context work = Context.open_isolated_named("pooled");
  String result = _summary_pooled();
  work.close();
  return result;
}

static void summary_loop_calls(List values) {
  while (values) {
    (void) _summary_direct();
    (void) _summary_transitive();
    (void) _summary_static();
    (void) _summary_recursive_seed(0);
    (void) summary_public();
    (void) _summary_pooled();
    (void) _summary_recursive();
    (void) _summary_indirect(NULL);
    (void) _summary_mixed(1);
    (void) _summary_converted();
    (void) summary_ambiguous();
    (void) summary_missing();
    values = cdr(values);
  }
}
