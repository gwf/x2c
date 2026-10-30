/*  hello-worlds.x -- twelve idiomatic paths to Hello, World! */

macro Expression $loud(Expr $s) => $s.upper();                  // typed macro

macro Expression $greet(Literal $who) => %"Hello, $($who)!";    // literal hole

int main(void) {
  _hello_machine();
  _string_chain();
  _word_pipeline();
  _partitioned();
  _list_dsl();
  _map_decoder();
  _array_sort();
  _closure_pipeline();
  _iterator_deltas();
  _runtime_lisp();
  _compile_time_meta();
  _greeting_macro();
  return 0;
}

/*  hello-world: hello machine  */
static void _hello_machine(void) {
  String hi = %"He$($lower("LL"))o";                            // meta call
  List tail = %("World"), words = %($hi @tail);                 // List + $/@
  Array back = [words[1], words[0]];                            // Array
  Map machine = {parts: back};                                  // Map + Symbol
  auto Lisp lisp = Lisp.new();                                  // RT Lisp
  List parts = machine[<parts>].array();                        // methods
  List order = lisp.eval(%(reverse (quote $parts)));            // code/data
  (String hello, String world) = order;                         // destructure
  List done = order.map(%!(w) => bang($loud(w.string())))       // lambda + map
    .filter(%!(w) => w.string().len());                         // filter
  match (done) {                                                // match
    case %("HELLO!" "WORLD!"):                                  // List pattern
      puts(%"$hello, $world!");                                 // str interp
  }
}

static Var bang(Var s) { return %"$(s.string())!"; }            // Var -> Var

/*  hello-world: string chain  */
static void _string_chain(void) {
  String noise = "__dlroW__olleH__";
  String order = noise.strip("_").replace("__", " ")[::-1];
  puts(", ".join(order.split(" ")) + "!");
}

/*  hello-world: word pipeline  */
static void _word_pipeline(void) {
  List words = "---hello---world---".split("---")
    .filter(%!(String word) => word)
    .map(%!(String word) => word.capitalize());
  puts(", ".join(words) + "!");
}

/*  hello-world: partitioned  */
static void _partitioned(void) {
  (String hello, String slash, String world) =
    "hello/world".partition("/");
  String comma = slash.replace("/", ", ");
  puts(%"$(hello.capitalize())$comma$(world.capitalize())!");
}


/*  hello-world: list DSL  */
static void _list_dsl(void) {
  List hello = %(script (title hello) (text ", ")
                        (title world) (text "!"));
  puts(_render(hello));
}

static String _render(List form) {
  match (form) {
    case %(text ?value): return value.str();
    case %(title ?value): return value.str().capitalize();
    case %(script *forms): return "".join(forms.map(_render));
  }
  raise %(bad-arg (operation "_render"));
}

/*  hello-world: map decoder  */
static void _map_decoder(void) {
  Map decoder = {uryyb: "Hello", jbeyq: "World"};
  List cipher = %(uryyb jbeyq);
  puts(", ".join(cipher.map(%!(Symbol key) => decoder[key])) + "!");
}

/*  hello-world: array sort  */
static void _array_sort(void) {
  Array puzzle = ["08:o", "00:H", "12:!", "06: ", "03:l",
                    "10:l", "01:e", "11:d", "05:,", "09:r",
                    "04:o", "07:W", "02:l"];
  String greeting = puzzle.sort()
    .map(%!(String piece) => piece[3:]).join("");
  puts(greeting);
}


/*  hello-world: closure pipeline  */
static void _closure_pipeline(void) {
  Func speech = %!(String text) => text;
  foreach(String word in %("Hello" ", " "World" "!"))
    speech = _then(speech, _says(word));
  String greeting = speech(%"");
  puts(greeting);
}

static Func _says(String word) {
  return %!(String text) => text + word;
}

static Func _then(Func first, Func next) {
  return %!(String text) => next(first(text));
}

/*  hello-world: iterator deltas  */
static void _iterator_deltas(void) {
  List deltas = %(72 29 7 0 3 -67 -12 55 24 3 -6 -8 -67);
  String greeting = deltas.iter()
    .scan(0, %!(int sum, int step) => sum + step)
    .map(%!(int byte) => String.new_fill((char) byte, 1))
    .array().join("");
  puts(greeting);
}

/*  hello-world: runtime Lisp  */
static void _runtime_lisp(void) {
  auto Lisp lisp = Lisp.new();
  lisp.eval(%(defun greet (name)
    (string-append "Hello, " name "!")));
  String greeting = lisp.eval(%(greet "World"));
  puts(greeting);
}

/*  hello-world: compile-time meta  */
static void _compile_time_meta(void) {
  puts($joined("Hel", "lo, ", "Wor", "ld!"));
}

/*  hello-world: greeting macro  */
static void _greeting_macro(void) {
  puts($greet("World"));
}

meta static String lower(String s) => s.lower();                // meta

meta static String joined(String a, String b, String c, String d) =>
  a + b + c + d;
