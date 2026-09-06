int dataset_src_public(void);

static int dataset_lib_helper(void) {
  return 2;
}

int dataset_lib_public(void) {
  return dataset_lib_helper();
}

static int dataset_lib_to_src(void) {
  return dataset_src_public();
}

static int dataset_lib_internal(void) {
  return dataset_lib_public();
}
