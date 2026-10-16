#pragma indent

int membership(String text):
  int found = text.contains("====")
  return found

int bracket_tight(String text):
  return (text.contains("x")
    + 1)

int bracket_loose(String text):
  return (text.contains("x")
    )

int operator_continuation(String text):
  return text.contains("x")
    + 1

int negated(String text):
  return !text.contains("x")

int deeper_continuation(String text):
  return text.contains("x")
    == 1

int continued_statement(String text):
  int found =
    text.contains("x")
    + 1
  return found

int final_statement(String text):
  return text.contains("last")

int trailing_comment(String text):
  int found = text.contains("comment") // keep the comment
  // between statements
  return found

int multiline_receiver(String text):
  return text
    .contains("x")

List quoted_call(void):
  return %(text.contains("x"))

int deeper_word(String text, Array values):
  return text.contains("x")
    in values

Var member_continuation(String text):
  return text.contains("x")
  .var()

int final_call(String text):
  return text.contains("end")
