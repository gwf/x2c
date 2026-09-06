typedef int (*SiteCallback)(int);

typedef struct SiteOwner {
  int value;
  int values[2];
} *SiteOwner;

int site_global = 3;

static int site_make(void) {
  return 1;
}

static void site_target(
  int parameter_value, int local_value, int field_value, int call_value,
  int literal_value, int operator_value, int index_value, int cast_value,
  List list_value, Map map_value, Array array_value, int computed_value,
  int global_value, size_t form_value) {
  (void) parameter_value;
  (void) local_value;
  (void) field_value;
  (void) call_value;
  (void) literal_value;
  (void) operator_value;
  (void) index_value;
  (void) cast_value;
  (void) list_value;
  (void) map_value;
  (void) array_value;
  (void) computed_value;
  (void) global_value;
  (void) form_value;
}

static void site_shapes(
  int parameter, SiteOwner owner, SiteCallback callback) {
  int local = site_make();
  site_target(
    parameter, local, owner.value, site_make(), 7, local + 1,
    owner.values[0], (int) local, %(parameter), %{}, %[], callback(1),
    site_global, sizeof(int)
  );
  site_target(
    parameter, local, owner.value, site_make(), 7, local + 1,
    owner.values[0], (int) local, %(parameter), %{}, %[], callback(1),
    site_global, sizeof(int)
  );
  local = 9;
  site_target(
    parameter, local, owner.value, site_make(), 7, local + 1,
    owner.values[0], (int) local, %(parameter), %{}, %[], callback(1),
    site_global, sizeof(int)
  );
}

static void site_branches(
  int parameter, SiteOwner owner, SiteCallback callback) {
  int local = site_make();
  if (parameter) local = 4;
  else local = 5;
  site_target(
    parameter, local, owner.value, site_make(), 7, local + 1,
    owner.values[0], (int) local, %(parameter), %{}, %[], callback(1),
    site_global, sizeof(int)
  );
}

static void site_mutations(
  int parameter, SiteOwner owner, SiteCallback callback) {
  int local = site_make();
  local += 2;
  local++;
  site_target(
    parameter, local, owner.value, site_make(), 7, local + 1,
    owner.values[0], (int) local, %(parameter), %{}, %[], callback(1),
    site_global, sizeof(int)
  );
}

static void shared_site(int value) {
  (void) value;
}

static void first_shared_caller(void) {
  shared_site(1);
}

static int site_initialized = site_make();
