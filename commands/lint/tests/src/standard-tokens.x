/* Token and declaration signals with inert references and field names. */
#include <stdio.h>

typedef struct State {
  int old_field, saved_field, previous_field;
} State;

void report_error(int code, String message);

int standard_tokens(int ready, State &state) {
  if (ready) {
    ready++;
    ready++;
  } else ready--;
  String empty = String.new("");
  Array items = Array.new();
  Map names = Map.new();
  int old_ready = ready;
  int count = 0, saved_ready = ready;
  for (int previous_ready = ready; previous_ready > 0; previous_ready--)
    count++;
  state.old_field = ready;
  count += saved_ready + old_ready;
  String text = String.new("filled");
  (void) text; (void) empty; (void) items; (void) names;
  if ((ready = count)) report_error(1, "expected a count");
  if ((ready += count)) count++;
  while ((ready = count)) break;
  for (; (ready = count);) break;
  while ((ready = fread(&count, sizeof count, 1, stdin)) > 0) count++;
  for (; (ready = fread(&count, sizeof count, 1, stdin)) > 0;) count++;
  return count;
}

macro Expression $fixture.ident() => $(x2c.ident "standard_tokens");
$(defun chosen_lisp (n) (+ n 1))

int standard_refs(int old_parameter, State &state) {
  String text = "$(x2c.ident), $(defun), Array.new(), } else";
  return old_parameter + state.saved_field + state.previous_field + text.len();
}
