#pragma indent
// Indented macros from an .xpmacro import, decorators, and match.
$(import "indent-macros.xpmacro")

static List simplify(List node):
  match node:
    case %(if (not ?condition) ?yes ?no):
      return simplify(%(if $condition $no $yes))
    case %(if true ?yes ?): return simplify(yes)
    case %(block *body):
      return %(block @{body.map(%!(List item) => simplify(item))})
    default: return node

int positive(int x):
  @$indent.fallback(-1)
  if x > 0: return x

int main(void):
  int total = 0, left = 20, right = 22
  @$indent.range(i, 2, 5)
  total += i
  $indent.swap(left, right)
  printf("%d %d %d %d\n", total, left, right, $indent.answer(40))
  printf("%d %d\n", positive(7), positive(-7))
  List code = %(block (if (not ready) (call wait) (call start)))
  puts(simplify(code).str())
  %(if true (call save) (call discard)).len()
  return 0
