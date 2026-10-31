typedef void Empty;
typedef Empty Again;
typedef int (*Callback)(Again);

static int count(Again);
static int count(Again) { return 7; }

static int via_pointer(Callback callback) { return callback(); }
static int has_null(Empty *value) { return value == NULL; }

int main(Empty) {
  Callback callback = count;
  Func wrapped = count;
  printf("%d %d %d %d\n", count(), via_pointer(callback),
         wrapped().int(), has_null(NULL));
  return 0;
}
