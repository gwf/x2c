typedef int (*DatasetCallback)(int);

typedef struct DatasetValue {
  int number;
} *DatasetValue;

int dataset_lib_public(void);
int dataset_external(void);

static int dataset_src_helper(void) {
  return 1;
}

int DatasetValue.read(DatasetValue value) {
  return value->number;
}

int dataset_src_public(void) {
  return dataset_src_helper();
}

static int dataset_src_repeated(void) {
  return dataset_src_helper() + dataset_src_helper();
}

static int dataset_src_to_lib(void) {
  return dataset_lib_public();
}

static int dataset_src_external(void) {
  return dataset_external();
}

static int dataset_src_indirect(DatasetCallback callback) {
  return callback(1);
}

static int dataset_src_initialized = dataset_src_helper();
