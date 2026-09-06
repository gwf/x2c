/* Built-in source-macro foreach parity.

   Cursor-backed collections keep their native outputs, while every other
   iterable uses the Iter protocol. Each declaration belongs only to its loop.
*/
#include "x2c.x"
#include "typed-map.x"

static int map_evaluations;
static int split_evaluations;
static int initializer_evaluations;
static int cleanups;

static Map counted_map(Map map) {
  map_evaluations++;
  return map;
}

static Split counted_words(String text) {
  split_evaluations++;
  return text.words();
}

static int initial_value(void) {
  initializer_evaluations++;
  return 99;
}

static void record_cleanup(void) {
  cleanups++;
}

int main(void) {
  Map counts = %{"a": 1, "b": 2, "c": 3};

  List values = %(1 2 3);
  int existing = 0, existing_total = 0;
  foreach(int current, values) {
    existing = current;
    existing_total += existing;
  }

  int value_total = 0;
  foreach(Var value, counts) value_total += value.integer();

  int typed_total = 0;
  foreach(int value = initial_value(), counted_map(counts))
    typed_total += value;

  Var entry = void;
  int existing_map_total = 0;
  foreach(Var current, counts) {
    entry = current;
    existing_map_total += entry.integer();
  }

  int key_bytes = 0, destructured_total = 0;
  foreach(Var (name, count), counts) {
    key_bytes += name.string().len();
    destructured_total += count.integer();
  }

  Map numbers = %{1: 10, 2: 20};
  int converted_total = 0, key_total = 0;
  foreach(int (key, count), numbers) converted_total += key + count;
  foreach(int key, numbers.keys()) key_total += key;

  int skipped = 0, stopped = 0;
  foreach(Var value, counts) {
    if (value.integer() == 2) continue;
    skipped += value.integer();
  }
  foreach(Var value, counts) {
    if (value) stopped++;
    break;
  }

  int deferred_keys = 0;
  foreach(Var (name, value), counts) {
    defer record_cleanup();
    if (name.string() && value) deferred_keys++;
  }

  int nested = 0;
  foreach(Var outer, counts)
    foreach(Var inner, counts)
      nested += outer.integer() * inner.integer();

  int caught = 0;
  try {
    foreach(Var value, counts) {
      defer record_cleanup();
      if (value) raise %(invariant);
    }
  }
  catch %(invariant): caught = 1;

  int word_bytes = 0;
  foreach(String word, %"  alpha beta  gamma ".words())
    word_bytes += word.len();

  int line_count = 0, line_bytes = 0;
  foreach(String line, %"one\ntwo\r\nthree\n".lines()) {
    line_count++;
    line_bytes += line.len();
  }

  int fields = 0, empty_fields = 0;
  foreach(String field, %"a::b:".splits(%":")) {
    fields++;
    if (!field.len()) empty_fields++;
  }

  String word = NULL;
  int scanned_bytes = 0;
  foreach(String current, counted_words(%"one two three")) {
    word = current;
    scanned_bytes += word.len();
  }

  int pairs = 0;
  foreach(String left, %"a b".words())
    foreach(String right, %"1 2 3".words())
      if (left && right) pairs++;

  int boxed = 0;
  foreach(Var field, %"x y".words()) boxed += field.string().len();

  struct Iter zip_left_storage, zip_right_storage, zip_storage;
  Iter zip_left = %("a" "bb").iter(&zip_left_storage);
  Iter zip_right = range(1, 2, 1, &zip_right_storage);
  Iter zipped = zip_left.zip(zip_right, &zip_storage);
  int zipped_total = 0;
  foreach(Var (text, number), zipped)
    zipped_total += text.string().len() * number.integer();

  MapIntInt counted = MapIntInt.new();
  counted.set(1, 10);
  counted.set(2, 20);
  int native_values = 0, native_pairs = 0;
  foreach(int value, counted) native_values += value;
  foreach(int (key, value), counted) native_pairs += key * value;

  MapStringString named = MapStringString.new();
  named.set(%"ada", %"lovelace");
  int native_bytes = 0;
  foreach(String value, named) native_bytes += value.len();

  // Reusing a loop declaration spelling after expansion must remain legal.
  int value = 7;

  printf(
    "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
    value_total, typed_total, key_bytes, destructured_total,
    converted_total, skipped, stopped, deferred_keys, nested, caught,
    cleanups, map_evaluations, initializer_evaluations, word_bytes,
    line_count, line_bytes, fields, empty_fields, scanned_bytes,
    split_evaluations
  );
  printf("%d %d %d %d %d %d %d %d %d %d\n", pairs, boxed, zipped_total,
         native_values, native_pairs, native_bytes, key_total, existing,
         existing_total, existing_map_total);
  return value_total == 6 && typed_total == 6 && key_bytes == 3 &&
         destructured_total == 6 && converted_total == 33 && skipped == 4 &&
         stopped == 1 && deferred_keys == 3 && nested == 36 && caught == 1 &&
         cleanups == 4 && map_evaluations == 1 &&
         initializer_evaluations == 1 && word_bytes == 14 &&
         line_count == 3 && line_bytes == 11 && fields == 4 &&
         empty_fields == 2 && scanned_bytes == 11 &&
         split_evaluations == 1 && pairs == 6 && boxed == 2 &&
         zipped_total == 5 && native_values == 30 && native_pairs == 50 &&
         native_bytes == 8 && key_total == 3 && existing == 3 &&
         existing_total == 6 && existing_map_total == 6 &&
         entry is not void && word == %"three" && value == 7 ? 0 : 1;
}
