macro Decorator $keep(Function $function) { @Code.body($function) }
static int before_decorated(void) => 1;
$keep()
int decorated(void) => before_decorated();
int after_decorated(void) => decorated();

#define META_BOUNDARY 1
static int before_meta(void) => 2;
meta int pure_meta(void) => 3;
int after_meta(void) => before_meta();

#define RESUME_ORDINARY 1
int ordinary_leaf(void) => 1;
int ordinary_caller(void) => ordinary_leaf();

#define PRAGMA_PRIVATE 1
#pragma private
int pragma_leaf(void) => 1;
int pragma_caller(void) => pragma_leaf();
#pragma public

static int with_directive(void) {
#define INSIDE_FUNCTION 1
  return INSIDE_FUNCTION;
}
int after_directive(void) => with_directive();
