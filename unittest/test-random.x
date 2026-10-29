/*  test-random.x -- unit tests for pseudorandom numbers and UUIDs */

#include "random.x"
#include "test-support.x"
#include "test-macros.x"

/* Returns the `offset` of the `<malformed>` that parsing `text` raises, or
   -1 if it parsed. */
static int _rejected_at(String text) {
  try Uuid.parse(text);
  catch %(malformed *detail): return detail.assoc(<offset>).int();
  return -1;
}

/* The first outputs of the reference xoshiro256** seeded through the
   reference SplitMix64 from 42, from prng.di.unimi.it. */
static void random_matches_reference_sequence(void) {
  $test.scoped();
  Random r = Random.new(42);
  EXPECT_TRUE(r.next() == 1546998764402558742ULL);
  EXPECT_TRUE(r.next() == 6990951692964543102ULL);
}

static void random_copies_continue_independently(void) {
  $test.scoped();
  Random r = Random.new(7);
  r.next();
  Random copy = r;
  uint64_t first = r.next();
  EXPECT_TRUE(copy.next() == first);
  Random other = Random.new(8), same = Random.new(7);
  EXPECT_FALSE(other.next() == same.next());
}

static void random_below_stays_in_range(void) {
  $test.scoped();
  Random r = Random.new(1);
  int counts[6] = {0};
  for (int i = 0; i < 60000; i++) {
    long roll = r.below(6);
    if (!EXPECT_TRUE(roll >= 0 && roll < 6)) return;
    counts[roll]++;
  }
  for (int i = 0; i < 6; i++)
    EXPECT_TRUE(counts[i] > 9000 && counts[i] < 11000);
  EXPECT_INT_EQ(r.below(1), 0);
  long large = r.below(LONG_MAX);
  EXPECT_TRUE(large >= 0);
  int caught = 0;
  try r.below(0);
  catch %(bad-arg (operation "Random.below") *): caught++;
  EXPECT_INT_EQ(caught, 1);
}

static void random_double_is_in_unit_interval(void) {
  $test.scoped();
  Random r = Random.new(3);
  double sum = 0;
  for (int i = 0; i < 10000; i++) {
    double x = r.double();
    if (!EXPECT_TRUE(x >= 0 && x < 1)) return;
    sum += x;
  }
  EXPECT_TRUE(sum / 10000 > 0.45 && sum / 10000 < 0.55);
}

static void random_shuffle_permutes_in_place(void) {
  $test.scoped();
  Random r = Random.new(5);
  Array items = [1, 2, 3, 4, 5, 6, 7, 8];
  r.shuffle(items);
  EXPECT_INT_EQ(items.len(), 8);
  EXPECT_TRUE(Var.equal(items.copy().sort(), [1, 2, 3, 4, 5, 6, 7, 8]));
  Array again = [1, 2, 3, 4, 5, 6, 7, 8];
  Random replay = Random.new(5);
  replay.shuffle(again);
  EXPECT_TRUE(Var.equal(items, again));
  Array empty = [];
  r.shuffle(empty);
  EXPECT_INT_EQ(empty.len(), 0);
}

static void random_choice_draws_an_element(void) {
  $test.scoped();
  Random r = Random.new(9);
  Array items = ["a", "b", "c"];
  for (int i = 0; i < 20; i++) EXPECT_TRUE(r.choice(items) in items);
  int caught = 0;
  try r.choice([]);
  catch %(bad-arg (operation "Random.choice") *): caught++;
  EXPECT_INT_EQ(caught, 1);
}

static void random_secure_fill_varies(void) {
  $test.scoped();
  unsigned char first[32] = {0}, second[32] = {0};
  Random.secure_fill(first, sizeof first);
  Random.secure_fill(second, sizeof second);
  EXPECT_TRUE(memcmp(first, second, sizeof first) != 0);
  Random a = Random.from_entropy(), b = Random.from_entropy();
  EXPECT_FALSE(a.next() == b.next());
}

static void random_uuid_v4_is_canonical(void) {
  $test.scoped();
  String id = Uuid.v4();
  EXPECT_INT_EQ(id.len(), 36);
  EXPECT_TRUE(Uuid.is_valid(id));
  EXPECT_STR_EQ(Uuid.parse(id), id);
  EXPECT_TRUE(id[14] == '4');
  EXPECT_TRUE(strchr("89ab", id[19]) != NULL);
  EXPECT_STR_EQ(id.lower(), id);
  EXPECT_FALSE(Uuid.v4() == id);
}

static void random_uuid_parse_validates(void) {
  $test.scoped();
  EXPECT_STR_EQ(Uuid.parse("9F6E2C1A-0B7D-4E3F-A2C5-6D8E9F0A1B2C"),
                "9f6e2c1a-0b7d-4e3f-a2c5-6d8e9f0a1b2c");
  EXPECT_INT_EQ(_rejected_at("9f6e2c1a-0b7d-4e3f-a2c5-6d8e9f0a1b2"), 35);
  EXPECT_INT_EQ(_rejected_at("9f6e2c1a+0b7d-4e3f-a2c5-6d8e9f0a1b2c"), 8);
  EXPECT_INT_EQ(_rejected_at("9f6e2c1a-0b7d-4e3f-a2c5-6d8e9f0a1b2cd"), 36);
  EXPECT_INT_EQ(_rejected_at("g f6e2c1a-0b7d-4e3f-a2c5-6d8e9f0a1b2c"), 0);
  EXPECT_INT_EQ(_rejected_at(""), 0);
  EXPECT_FALSE(Uuid.is_valid("{9f6e2c1a-0b7d-4e3f-a2c5-6d8e9f0a1b2c}"));
}

void random_suite(void) {
  $test.run(random_matches_reference_sequence);
  $test.run(random_copies_continue_independently);
  $test.run(random_below_stays_in_range);
  $test.run(random_double_is_in_unit_interval);
  $test.run(random_shuffle_permutes_in_place);
  $test.run(random_choice_draws_an_element);
  $test.run(random_secure_fill_varies);
  $test.run(random_uuid_v4_is_canonical);
  $test.run(random_uuid_parse_validates);
}
