/* A switch on a String selects its case by content and keeps C switch
   control flow. Switches with the same selector type and labels share one
   helper. */

typedef String Color;
static int calls = 0;

static String next(String s) {
  calls++;
  return s;
}

/* Fallthrough, adjacent labels, default last, and the empty label. */
static String classify(String s) {
  String out = "";
  switch (next(s)) {
    case "apple":
      out += "apple>";
    case "pear": case "plum":
      out += "fruit";
      break;
    case "":
      out += "empty";
      break;
    default:
      out += "other";
  }
  return out;
}

/* An alias selector with default first. Tone and shade have the same
   labels, so they share one helper. */
static int tone(Color c) {
  switch (c) {
    default: return 0;
    case "red": return 1;
    case "blue": return 2;
  }
}

static int shade(Color c) {
  switch (c) {
    case "red": return 10;
    case "blue": return 20;
  }
  return -1;
}

/* A nested String switch, a nested integer switch, and a label inside a
   nested block. */
static String nested(String outer, String inner, int k) {
  switch (outer) {
    case "a":
      switch (inner) {
        case "x": return "a.x";
        case "y": break;
        default: return "a.?";
      }
      return "a.y";
    case "b":
      switch (k) {
        case 1: return "b.1";
        case 2: return "b.2";
      }
      if (inner == "deep") {
        case "c": return "b-or-c";
      }
      return "b";
  }
  return "none";
}

/* Break and continue inside a loop. */
static int count(String *words, int n) {
  int kept = 0;
  for (int i = 0; i < n; i++) {
    switch (words[i]) {
      case "skip": continue;
      case "stop": return kept;
      case "two" "!": kept += 10; break;
      default: kept++;
    }
    kept += 100;
  }
  return kept;
}

#define CASE_WORD "word"

static int escaped_labels(String value) {
  switch (value) {
    case "a\0tail": return 1;
    case "atail": return 2;
    case "\x025i": return 3;
    case "\0025i": return 4;
    case "\u00A9": return 5;
    case "A9": return 6;
    case "pre" CASE_WORD "post": return 7;
    case "prepost": return 8;
  }
  return 0;
}

int main(void) {
  String built = "pl" + "um";
  Stdout.printf("%s %s %s\n", classify("apple"), classify(built),
                classify("kiwi"));
  Stdout.printf("%s %s calls=%d\n", classify(""), classify(NULL), calls);
  Stdout.printf("%d %d %d %d %d\n", tone("red"), tone("blue"), tone("x"),
                shade("blue"), shade("x"));
  Stdout.printf("%s %s %s\n", nested("a", "x", 0), nested("a", "y", 0),
                nested("a", "z", 0));
  Stdout.printf("%s %s %s %s %s\n", nested("b", "q", 1),
                nested("b", "deep", 0), nested("b", "q", 0),
                nested("c", "q", 0), nested("d", "q", 0));
  String words[] = { "x", "skip", "two!", "", "stop", "z" };
  Stdout.printf("count=%d\n", count(words, 6));
  printf("escapes=%d %d %d %d %d %d %d %d\n",
         escaped_labels("a"), escaped_labels("atail"), escaped_labels("%i"),
         escaped_labels("\0025i"), escaped_labels("\u00A9"),
         escaped_labels("A9"), escaped_labels("prewordpost"),
         escaped_labels("prepost"));
  return 0;
}
