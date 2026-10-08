#include "match-component.x"
/* Each function prints what it saw, so the output with the component
   must equal the output of the same file without its include. */

static int evaluations = 0;
static List counted(List value) { evaluations++; return value; }

/* Arm order, literals of each kind, nested Lists, and the default. */
static String classify(List value) {
  match (counted(value)) {
    case %(point ?x ?y): return %"point $x $y";
    case %(point ?x ?y ?z): return %"point3 $x $y $z";
    case %(point *rest): return %"point* ${rest.len()}";
    case %(num 3 "three" -4 a-long-atom-name): return "literals";
    case %(pair ?a ?a): return %"same $a";
    case %(pair ?a ?b): return %"pair $a $b";
    case %(tree (node ?l ?r) ()): return %"tree $l $r";
    case %(tree (node *) ?leaf): return %"tree* $leaf";
    case %(text ?(String s) ?(List items)): return %"text $s ${items.len()}";
    case %(tag (!is type symbol) *): return "tag";
    case %(?head): return %"single $head";
    case %(*): return "other";
  }
  return "unreached";
}

/* A false guard tries the next arm; a guard sees the arm's captures and
   runs once per arm whose pattern matched. */
static int guard_runs = 0;
static int above(Var x, int limit) { guard_runs++; return x.int() > limit; }

static String guarded(List value, int limit) {
  String seen = "";
  match (value) {
    case %(n ?x) if (above(x, limit)): seen = %"big $x";
    case %(n ?x) if (x.int() == limit): seen = %"equal $x";
    case %(n ?x): seen = %"small $x";
    default: seen = "none";
  }
  return seen;
}

/* `break` leaves the match; `continue` reaches the loop; defer runs at
   each exit of its arm. */
static String loop(List items) {
  String log = "";
  foreach (Var item, items) {
    match (item) {
      case %(skip): continue;
      case %(stop): break;
      case %(defer ?name): {
        log = log + %"[$name";
        defer log = log + "]";
        if (name == <b>) break;
        log = log + "-";
      }
      case %(keep ?n): log = log + %"k$n";
      case %(again ?n): {
        defer log = log + ")";
        log = log + %"($n";
        continue;
      }
    }
    log = log + ".";
  }
  return log;
}

/* A binder shadows an outer name only in its arm. */
static String shadow(void) {
  Var value = 99;
  match (%(pair 1 2)) {
    case %(pair ?value ?other): printf("inside %d %d\n", value, other);
  }
  return %"outside $value";
}

/* No arm matches and there is no default: nothing happens. */
static int nothing(List value) {
  int hits = 0;
  match (value) case %(only ?x): hits += x.int();
  return hits;
}

/* A star binds the whole of a nil subject. */
static int rest_length(List value) {
  match (value) case %(*rest): return rest.len() + 10;
  return -1;
}

/* A repeated typed capture still compares the two values. */
static String twice(List value) {
  match (value) {
    case %(eq ?(String s) ?s): return %"twice ${s.len()}";
    case %(eq ?(String s) ?): return %"once $s";
  }
  return "neither";
}

/* A nested match, and a Var subject. */
static String nested(Var value) {
  match (value) {
    case %(outer ?inner):
      match (inner) {
        case %(inner ?x): return %"nested $x";
        default: return "inner other";
      }
    default: return "outer other";
  }
  return "unreached";
}

/* Matches the component declines still compile as before. */
static String declined(List value, Symbol wanted) {
  match (value) {
    case %(a * ?last): return %"interior $last";
    case %(b (!or x y)): return "alternative";
    case %(c $wanted): return "computed";
  }
  return "declined other";
}

int main(void) {
  List cases = %(
    (point 1 2) (point 1 2 3) (point) (point 1 2 3 4)
    (num 3 "three" -4 a-long-atom-name) (num 3 "3" -4 a-long-atom-name)
    (pair 5 5) (pair 5 6) (tree (node 1 2) ()) (tree (node 1 2) leaf)
    (text "hi" (1 2 3)) (text 7 (1 2 3)) (tag t 1) (tag "t") (solo) ());
  foreach (List value, cases)
    printf("%s -> %s\n", value.str(), classify(value));
  printf("evaluations %d\n", evaluations);
  printf("classify nil -> %s\n", classify(NULL));
  for (int limit = 4; limit <= 6; limit++)
    printf("guard %d: %s %s\n", limit, guarded(%(n 5), limit),
           guarded(%(m 5), limit));
  printf("guard runs %d\n", guard_runs);
  printf("loop %s\n", loop(%((keep 1) (skip) (defer a) (defer b) (keep 2)
                             (again 7) (stop) (keep 3))));
  printf("rest %d %d\n", rest_length(NULL), rest_length(%(a b)));
  printf("%s %s %s\n", twice(%(eq "ab" "ab")), twice(%(eq "ab" "c")),
         twice(%(eq 1 1)));
  printf("%s\n", shadow());
  printf("nothing %d %d\n", nothing(%(only 4)), nothing(%(other 4)));
  printf("%s %s %s\n", nested(%(outer (inner 7))), nested(%(outer (x))),
         nested(%(x)));
  printf("%s %s %s %s\n", declined(%(a 1 2 3), <z>), declined(%(b y), <z>),
         declined(%(c z), <z>), declined(%(d), <z>));
  return 0;
}
