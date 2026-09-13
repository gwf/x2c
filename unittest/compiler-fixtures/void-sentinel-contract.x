#include "x2c.x"
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

static int rejected(void (*action)(void)) {
  pid_t pid = fork();
  if (pid < 0) return 0;
  if (pid == 0) {
    action();
    _exit(0);
  }
  int status = 0;
  if (waitpid(pid, &status, 0) != pid) return 0;
  return WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT;
}

static void store_list_void(void) {
  cons(void, NULL);
}

static void store_array_void(void) {
  Array array = %[];
  array.push(void);
}

static void store_map_void_key(void) {
  Map map = %{};
  map.set(void, 1);
}

static void store_map_void_value(void) {
  Map map = %{};
  map.set(<key>, void);
}

static void update_map_void_value(void) {
  Map map = %{};
  Var key = <key>;
  map.update_n(1, key, void);
}

static void construct_map_void_key(void) {
  Var key = void;
  Map map = %{ $key: 1 };
  (void) map;
}

static void construct_map_void_value(void) {
  Var val = void;
  Map map = %{ key: $val };
  (void) map;
}

static void construct_array_raw_void(void) {
  Array array = %[void];
  (void) array;
}

static int yield_void(Iter iter, Var *out) {
  (void) iter;
  *out = void;
  return 1;
}

static void iterate_void(void) {
  struct Iter storage;
  Var out;
  Iter iter = Iter.init(&storage, nil, yield_void, nil);
  iter.try_next(&out);
}

static void construct_zero_step_range(void) {
  struct Iter storage;
  range(0, 1, 0, &storage);
}

static int yield_once(Iter iter, Var *out) {
  if (iter.state.int()) return 0;
  *out = iter.obj;
  iter.state = 1;
  return 1;
}

static void unzip_value(Var value) {
  struct Iter source_storage, columns_storage, child_storage;
  UnzipShared shared;
  Iter source = Iter.init(&source_storage, value, yield_once, 0);
  Iter columns = Iter.unzip(source, &shared, &columns_storage);
  Var child = columns.next();
  Var.iter(child, &child_storage).next();
}

static void unzip_nil(void) {
  unzip_value(nil);
}

static void unzip_singleton(void) {
  unzip_value(%(1));
}

static void unzip_long_list(void) {
  unzip_value(%(1 2 3));
}

static void unzip_atom(void) {
  unzip_value(1);
}

static Var scan_to_void(Var acc, Var item) {
  (void) acc;
  (void) item;
  return void;
}

static void scan_void_result(void) {
  struct Iter source_storage, scan_storage;
  Iter source = range(0, 0, 1, &source_storage);
  Iter scan = Iter.scan(source, 0, scan_to_void, &scan_storage);
  scan.next();
}

int main(void) {
  int list = rejected(store_list_void);
  int array = rejected(store_array_void);
  int map_key = rejected(store_map_void_key);
  int map_value = rejected(store_map_void_value);
  int map_update = rejected(update_map_void_value);
  int map_literal_key = rejected(construct_map_void_key);
  int map_literal_value = rejected(construct_map_void_value);
  int array_literal_raw = rejected(construct_array_raw_void);
  int iter = rejected(iterate_void);
  int zero_range = rejected(construct_zero_step_range);
  int bad_unzip_nil = rejected(unzip_nil);
  int bad_unzip_single = rejected(unzip_singleton);
  int bad_unzip_long = rejected(unzip_long_list);
  int bad_unzip_atom = rejected(unzip_atom);
  int bad_scan = rejected(scan_void_result);
  printf("%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
         list, array, map_key,
         map_value, map_update, map_literal_key, map_literal_value,
         array_literal_raw, iter, zero_range, bad_unzip_nil, bad_unzip_single,
         bad_unzip_long, bad_unzip_atom, bad_scan);
  return list && array && map_key && map_value && map_update &&
         map_literal_key && map_literal_value && array_literal_raw && iter &&
         zero_range && bad_unzip_nil && bad_unzip_single && bad_unzip_long &&
         bad_unzip_atom && bad_scan ? 0 : 1;
}
