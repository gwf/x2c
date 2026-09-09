#include "x2c.x"

typedef String Text;

static void bad_guard(void) { raise %(failed); }

macro Statement $typed_arm(Expr $subject, Name $result) => {
  match ($subject)
    case %(text ?(String text)) if (text.len() == 4):
      $result = text.len();
}

macro Statement $typed_size(Type $T, Expr $subject, Name $result) => {
  match ($subject)
    case %(?($T value)): $result = sizeof(value);
}

macro Statement $constructed_guard(Expr $subject, Name $result) => {
  $(list
    `(match ,$subject
      (((*)
        (guarded
          (if (expr (int) (literal (int) "1"))
            (block
              (stmnt (expr () (op = (expr () (ident ,$result))
                (expr (int) (literal (int) "7")))))
              (break))))))))...
}

int main(void) {
  int spaced = 0;
  match (%(ignored (String text)))
    case %(? (String text)): spaced = 1;
  int result = 0, guards = 0;
  String text = %"outer";
  List subject = %(text "word");
  match (subject) {
    case %(text ?(int text)): result = -1;
    case %(text ?(String text)) if (++guards && text.len() > 5):
      result = -2;
    case %(text ?(String text)) if (++guards && text.len() == 4):
      result = text.len();
    default: result = -3;
  }
  printf("typed %d %d %s\n", result, guards, text.str());

  int repeated = 0;
  match (%("same" "same"))
    case %(?value ?(String value)): repeated = value.len();
  match (%("other" "same"))
    case %(?(String value) ?value): repeated = -1;
  printf("repeated %d\n", repeated);

  int alternative = 0;
  match (%(7 "later"))
    case %(!or (?value ?) (? ?(String value))):
      alternative = value.len();
  printf("alternative %d\n", alternative);

  int nested = 0;
  match (%(tag ("same" "same")))
    case %(tag (!and ?pair (?(String value) ?value))):
      nested = value.len() + pair.list().len();
  printf("nested %d\n", nested);

  int quoted = 0;
  match (%(?value "x"))
    case %((!quote ?value) ?(String value)): quoted = value.len();
  printf("quoted %d\n", quoted);

  int alias = 0, optional = 0;
  match (%("same" "same"))
    case %(?(String deliberately_long_capture_name)
           ?(Text deliberately_long_capture_name)):
      alias = deliberately_long_capture_name.len();
  match (%(right 7))
    case %(!or ?(List pair) (left ?) (right ?)): optional = pair.len();
  printf("aliases %d %d\n", alias, optional);

  void *raw = "raw";
  int pointer = 0;
  match (%(${raw})) {
    case %(?(String value)): pointer = -1;
    case %(?(void *value)): pointer = value == raw;
  }
  printf("pointer %d\n", pointer);

  int numeric = 0;
  match (%(7.0)) {
    case %(?(int value)): numeric = -1;
    case %(?(double value)): numeric = value == 7.0;
  }
  printf("numeric %d\n", numeric);

  int evaluations = 0, dynamic = 0;
  match (%("value" 5))
    case %(?(String value) ${++evaluations + 4}): dynamic = value.len();
  printf("dynamic %d %d\n", dynamic, evaluations);

  int cleanup = 0, final = 0, visited = 0, continued = 0, caught = 0;
  for (int i = 0; i < 3; i++) {
    match (%(tick ${i})) {
      case %(tick ?(int value)) if (value < 2): {
        defer cleanup++;
        try {
          visited++;
          if (!value) continue;
          break;
        }
        finally { final++; }
      }
      default if (i == 2): visited++;
    }
    continued++;
  }
  try {
    match (subject)
      case %(text ?(String value)) if ((bad_guard(), value.len())):
        visited = -1;
  }
  catch %(failed): caught++;
  printf("control %d %d %d %d %d\n",
         cleanup, final, visited, continued, caught);

  int macro_value = 0, constructed = 0, macro_size = 0;
  $typed_arm(subject, macro_value);
  $constructed_guard(subject, constructed);
  $typed_size(String, %("text"), macro_size);
  printf("macros %d %d %d\n", macro_value, constructed,
         macro_size == sizeof(String));
  return spaced == 1 && result == 4 && guards == 2 && text == "outer" &&
         repeated == 4 && alternative == 5 && nested == 6 && quoted == 1 &&
         alias == 4 && optional == 2 && pointer == 1 && numeric == 1 &&
         dynamic == 5 && evaluations == 1 &&
         cleanup == 2 && final == 2 &&
         visited == 3 && continued == 2 && caught == 1 &&
         macro_value == 4 && constructed == 7 &&
         macro_size == sizeof(String) ? 0 : 1;
}
