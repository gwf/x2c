#include "x2c.x"

typedef struct Env { const Var *values; int n; } Env;

static Env *kept = NULL;

static void bind_ptr(Env *env, const Var *values) { env.values = values; }
static void bind_ref(Env &env, const Var *values) { env.values = values; }
static void keep_ptr(Env *env) { kept = env; }
static void keep_ref(Env &env) { kept = &env; }
static Env *same_ptr(Env *env) => env;
static Env *same_ref(Env &env) => &env;

// A reference argument is the caller's object, as `&object` is for a pointer.
static int bound_in_frame(void) {
  Var values[2] = {1, 2};
  Env a = {0}, b = {0};
  bind_ptr(&a, values);
  bind_ref(b, values);
  return a.values == b.values;
}

// The object's address outlives the frame through either form.
static Env *escaped_ptr(void) {
  Env a = {0}, c = {0};
  keep_ptr(&a);
  return same_ptr(&c);
}

static Env *escaped_ref(void) {
  Env b = {0}, d = {0};
  keep_ref(b);
  return same_ref(d);
}

int main(void) {
  return bound_in_frame() + (escaped_ptr() != escaped_ref());
}
