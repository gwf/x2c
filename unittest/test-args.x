/*  test-args.x -- unit tests for parsing arguments against a spec */

#include "args.x"
#include "test-support.x"
$(import "test-macros.xmacro")

static List _spec(void) => %(
  (-v --verbose (help "Report each step"))
  (-o --output (value file) (default "a.out") (help "Write <file>"))
  (-I --include (value dir) repeated)
  (--prefix (value path) (help "Install under <path>"))
  (source required (help "The input file"))
  (rest repeated));

static void args_long_and_short_spellings(void) {
  $test.scoped();
  List spec = _spec();
  Map parsed = Args.parse(%("--output" "x" "--prefix=/opt" "main.x"), spec);
  EXPECT_STR_EQ(parsed["output"].str(), "x");
  EXPECT_STR_EQ(parsed["prefix"].str(), "/opt");
  EXPECT_STR_EQ(parsed["source"].str(), "main.x");
  parsed = Args.parse(%("-o" "y" "-Isrc" "-I" "lib" "main.x"), spec);
  EXPECT_STR_EQ(parsed["output"].str(), "y");
  EXPECT_LIST_EQ(parsed["include"].list(), %("src" "lib"));
  parsed = Args.parse(%("-vvoz" "main.x" "--include=a" "--output="), spec);
  EXPECT_INT_EQ(parsed["verbose"].integer(), 2);
  EXPECT_NULL(parsed["output"].str());
  EXPECT_LIST_EQ(parsed["include"].list(), %("a"));
  parsed = Args.parse(%("-o" "-v" "main.x"), spec);
  EXPECT_STR_EQ(parsed["output"].str(), "-v");
  EXPECT_INT_EQ(parsed["verbose"].integer(), 0);
  parsed = Args.parse(%(-v --prefix /usr main.x), spec);
  EXPECT_STR_EQ(parsed["prefix"].str(), "/usr");
}

static void args_defaults_fill_every_name(void) {
  $test.scoped();
  Map parsed = Args.parse(%("main.x"), _spec());
  EXPECT_INT_EQ(parsed.len(), 6);
  EXPECT_INT_EQ(parsed["verbose"].integer(), 0);
  EXPECT_FALSE(parsed["verbose"] ? 1 : 0);
  EXPECT_STR_EQ(parsed["output"].str(), "a.out");
  EXPECT_TRUE(parsed["include"] is List);
  EXPECT_NULL(parsed["include"].list());
  EXPECT_TRUE(parsed["prefix"] is String);
  EXPECT_FALSE(parsed["prefix"] ? 1 : 0);
  EXPECT_NULL(parsed["rest"].list());
  parsed = Args.parse(%("-Ione" "main.x"), %(
    (-I (value dir) repeated (default ("base")))
    (source)));
  EXPECT_LIST_EQ(parsed["I"].list(), %("one"));
  EXPECT_LIST_EQ(Args.parse(%(), %((-I (value dir) repeated
                                   (default ("base")))))["I"].list(),
                 %("base"));
}

static void args_operands_and_double_dash(void) {
  $test.scoped();
  List spec = _spec();
  Map parsed =
    Args.parse(%("a" "-v" "b" "--" "-o" "--prefix" "-" ""), spec);
  EXPECT_STR_EQ(parsed["source"].str(), "a");
  EXPECT_INT_EQ(parsed["verbose"].integer(), 1);
  EXPECT_STR_EQ(parsed["output"].str(), "a.out");
  List rest = parsed["rest"];
  EXPECT_INT_EQ(rest.len(), 5);
  EXPECT_STR_EQ(rest.car().str(), "b");
  EXPECT_STR_EQ(rest.cadr().str(), "-o");
  EXPECT_STR_EQ(rest.getindex(3).str(), "-");
  EXPECT_NULL(rest.getindex(4).str());
  parsed = Args.parse(%("--" "--verbose"), spec);
  EXPECT_STR_EQ(parsed["source"].str(), "--verbose");
  EXPECT_INT_EQ(parsed["verbose"].integer(), 0);
}

static Var _why(List args, List spec, Symbol subject) {
  Var result = (String) NULL;
  try Args.parse(args, spec);
  catch %(bad-arg *detail): {
    String why = detail.assoc(<why>).str();
    String text = detail.assoc(subject).str();
    result = %"$why: $text";
  }
  return result;
}

static void args_bad_input_raises(void) {
  $test.scoped();
  List spec = _spec();
  EXPECT_STR_EQ(_why(%("--bogus" "a"), spec, <option>).str(),
                "unknown option: --bogus");
  EXPECT_STR_EQ(_why(%("-vx" "a"), spec, <option>).str(),
                "unknown option: -x");
  EXPECT_STR_EQ(_why(%("a" "--output"), spec, <option>).str(),
                "missing value: --output");
  EXPECT_STR_EQ(_why(%("a" "-o"), spec, <option>).str(),
                "missing value: -o");
  EXPECT_STR_EQ(_why(%("--verbose=1" "a"), spec, <option>).str(),
                "unexpected value: --verbose");
  EXPECT_STR_EQ(_why(%("-v"), spec, <operand>).str(),
                "missing operand: source");
  EXPECT_STR_EQ(_why(%("a" "b"), %((source)), <operand>).str(),
                "unexpected operand: b");
  EXPECT_STR_EQ(_why(%("a"), %((-p --prefix (value p) required) (source)),
                     <option>).str(),
                "missing option: --prefix");
  EXPECT_STR_EQ(_why(NULL, %((-p (value p) required)), <option>).str(),
                "missing option: -p");
  EXPECT_STR_EQ(_why(NULL, %((-p (valeu p))), <spec>).str(),
                "unknown spec property: ( valeu p )");
  EXPECT_STR_EQ(_why(NULL, %((-p requird)), <spec>).str(),
                "unknown spec word: requird");
}

static void args_usage_lists_spec_rows(void) {
  $test.scoped();
  EXPECT_STR_EQ(Args.usage(_spec(), "tool"),
    "Usage:\n"
    "  tool [options] <source> [<rest>...]\n"
    "\n"
    "Options:\n"
    "  -v, --verbose               Report each step\n"
    "  -o, --output <file>         Write <file>\n"
    "  -I, --include <dir>\n"
    "      --prefix <path>         Install under <path>\n"
    "\n"
    "Operands:\n"
    "  <source>                    The input file\n");
  EXPECT_STR_EQ(Args.usage(%((files repeated required)), "cat"),
                "Usage:\n  cat <files>...\n");
  EXPECT_STR_EQ(Args.usage(NULL, "true"), "Usage:\n  true\n");
  EXPECT_INT_EQ(Args.parse(NULL, NULL).len(), 0);
  EXPECT_STR_EQ(
    Args.usage(
      %((--a-very-long-option-name (value placeholder) (help "Wraps"))),
      "tool"),
    "Usage:\n  tool [options]\n\nOptions:\n"
    "      --a-very-long-option-name <placeholder>\n"
    "                              Wraps\n");
}

static void args_from_argv_skips_the_program(void) {
  $test.scoped();
  char *argv[] = { "tool", "first", "second third", NULL };
  EXPECT_LIST_EQ(Args.from_argv(3, argv), %("first" "second third"));
  EXPECT_NULL(Args.from_argv(1, argv));
}

void args_suite(void) {
  $test.run(args_long_and_short_spellings);
  $test.run(args_defaults_fill_every_name);
  $test.run(args_operands_and_double_dash);
  $test.run(args_bad_input_raises);
  $test.run(args_usage_lists_spec_rows);
  $test.run(args_from_argv_skips_the_program);
}
