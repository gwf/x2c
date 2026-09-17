#include "x2c.x"

class Name String;
typedef String Label;

static long name_length(Name name) => name.len();
static long label_length(Label label) => label.len();
static Name default_name(void) => "build";
static Label default_label(void) => "main";
static const char *shown(String text) => text ? text : "NULL";

// A string literal initializes, assigns, passes, and returns either alias.
static void literals(void) {
  Name name = "src";
  Label label = "parse";
  Name assigned;
  Label renamed;
  assigned = "lib";
  renamed = "tokenizer";
  printf("%ld %ld %ld %ld\n", (long) name.len(), (long) label.len(),
         (long) assigned.len(), (long) renamed.len());
  printf("%s %s\n", %"$name/$label.x", %"$assigned/$renamed.x");
  printf("%ld %ld\n", name_length("unittest"), label_length("fixture"));
  Name built = default_name();
  Label main_label = default_label();
  printf("%ld %s/%s\n", (long) built.len(), built, %"$main_label.o");
  printf("%d %d\n", name == "src", label == "parse");
}

/* A C string beside an alias of String converts to String, so `+`
   concatenates through String.add. */
static void add(void) {
  Name name = String.new("build");
  Label label = String.new("main");
  String text = ".c";
  char *suffix = ".h", *prefix = "include/";
  const char *extension = ".x";
  String object = name + ".o", source = "src/" + label;
  printf("%s %s\n", object, source);
  printf("%s %s\n", label + suffix, prefix + name);
  printf("%s %s\n", name + text, name + "/" + label + text);
  printf("%s %s\n", text + extension, extension + label);
  name += ".d";
  printf("%s\n", name);
}

/* Equal text interned in sibling pools has distinct pointers, so only String
   equality reports these operands equal. */
static void equality(void) {
  Pool root = Pool.current();
  Pool left = root.retain(), right = root.retain();
  Name name = String.new_in(left, "build", 5);
  String text = String.new_in(right, "build", 5);
  Label label = String.new_in(root, "build", 5);
  printf("%d %d %d %d %d %d\n", name == text, text == name, label == text,
         text == label, name == label, label == name);
  printf("%d %d %d\n", name != text, text != label, label != name);
  printf("%d %d %d\n", name < text, text > label, label <= name);
  right.release();
  left.release();
}

static void var_conversion(void) {
  Var words = %(alpha beta), text = %"alpha", number = 42;
  foreach (Var value, %($words $text $number)) {
    String string = value;
    Name name = value;
    Label label = value;
    printf("%s %s %s\n", shown(string), shown(name), shown(label));
  }
  List mixed = %(symbol 2 (nested) "text");
  foreach (String string, mixed) printf(" %s", shown(string));
  printf("\n");
  foreach (Name name, mixed) printf(" %s", shown(name));
  printf("\n");
  foreach (Label label, mixed) printf(" %s", shown(label));
  printf("\n");
}

int main(void) {
  literals();
  add();
  equality();
  var_conversion();
  return 0;
}
