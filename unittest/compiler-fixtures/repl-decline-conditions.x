#include "x2c.x"
$(import "../../commands/repl/decline-errors.xmacro")

typedef struct DeclineState {
  int declined, calls;
  String reason;
} DeclineState;

static DeclineState state;
static int receivers, operands;
static List disturbance = %("unrelated" ("nested" 27));

static DeclineState *_state(void) { receivers++; return &state; }
static String _name(void) { operands++; return "missing"; }

static Var _lower_decline(DeclineState *lowering, String why) {
  lowering.calls++;
  if (!lowering.declined) {
    lowering.declined = 1;
    lowering.reason = why;
  }
  return void;
}

int main(void) {
  (void) disturbance;
  Var first = $layout_host(_state());
  Var second = $binding_missing(_state(), _name());
  if (first is not void || second is not void || state.calls != 2 ||
      receivers != 2 || operands != 1 ||
      state.reason != "a compile-time struct with no host layout") return 1;
  String why = $scan_goto();
  String missing = $scan_binding("native");
  if (why != "a goto has no lowering" || missing != "no binding for native" ||
      state.calls != 2 || state.declined != 1) return 1;
  puts("declines return and keep the first reason; scan reasons stay text");
  return 0;
}
