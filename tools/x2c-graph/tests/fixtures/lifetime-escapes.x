static void lifetime_native(char *value);

static char *lifetime_scope_alias(void) {
  Scope.retain();
  char *original = Scope.memdup("temporary", 10);
  char *alias = original;
  Scope.release();
  return alias;
}

static char *lifetime_scope_deferred(void) {
  Scope.retain();
  defer Scope.release();
  return Scope.calloc(1, 16);
}

static char *lifetime_scope_moved(Scope destination) {
  Scope.retain();
  char *result = Scope.memdup("survivor", 9);
  Scope.move(result, &destination);
  Scope.release();
  return result;
}

static char *lifetime_unknown(void) {
  Scope.retain();
  char *result = Scope.memdup("unknown", 8);
  lifetime_native(result);
  Scope.release();
  return result;
}

static Map lifetime_context_unexported(void) {
  Context work = Context.open_isolated_named("unexported");
  Map result = %{};
  work.close();
  return result;
}

static Map lifetime_context_exported(void) {
  Context work = Context.open_isolated_named("exported");
  Map result = %{};
  result = work.export(result.var()).map();
  work.close();
  return result;
}

static Map lifetime_context_ignored_export(void) {
  Context work = Context.open_isolated_named("ignored");
  Map result = %{};
  work.export(result.var());
  work.close();
  return result;
}

static String lifetime_context_deferred(void) {
  Context work = Context.open_isolated_named("deferred");
  defer work.close();
  return String.new("temporary");
}

static Map lifetime_context_mutable(void) {
  Context work = Context.open();
  Map result = %{};
  work.close();
  return result;
}

static String lifetime_context_inherited(void) {
  Context work = Context.open();
  String result = String.new("shared pool");
  work.close();
  return result;
}

static char *lifetime_indirect(void (*callback)(char *)) {
  Scope.retain();
  char *result = Scope.memdup("unknown", 8);
  callback(result);
  Scope.release();
  return result;
}

static char *lifetime_branch_unknown(int use) {
  Scope.retain();
  char *result = Scope.memdup("branch", 7);
  if (use) lifetime_native(result);
  Scope.release();
  return result;
}

static char *lifetime_branch_assignment(int replace) {
  Scope.retain();
  char *result = Scope.memdup("branch", 7);
  if (replace) result = NULL;
  Scope.release();
  return result;
}
