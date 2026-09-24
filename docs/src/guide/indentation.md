# Indentation Syntax

x2c can be written without braces or semicolons. Indentation groups the
statements of a block, a line that opens a block ends with `:`, and a line
break ends a statement. Name the file `.xp`, or put `#pragma indent` at the
top of a `.x` file. The two spellings mean the same program, so an indented
file can include, import, and call brace-form code and the reverse.

Here is a small program in brace form:

```x2c
typedef enum Shape { CIRCLE, SQUARE } Shape;

double area(Shape shape, double size) {
  switch (shape) {
    case CIRCLE: return 3.14159 * size * size;
    default: return size * size;
  }
}

int main(void) {
  double total = 0;
  for (int i = 1; i <= 3; i++) {
    if (i == 2) continue;
    total += area(i == 1 ? CIRCLE : SQUARE, i);
  }
  printf("%.2f\n", total);
  return 0;
}
```

```text
12.14
```

The same program in the indentation syntax:

```x2c
#pragma indent

typedef enum Shape:
  CIRCLE,
  SQUARE
Shape

double area(Shape shape, double size):
  switch shape:
    case CIRCLE: return 3.14159 * size * size
    default: return size * size

int main(void):
  double total = 0
  for int i = 1; i <= 3; i++:
    if i == 2: continue
    total += area(i == 1 ? CIRCLE : SQUARE, i)
  printf("%.2f\n", total)
  return 0
```

```text
12.14
```

Conditions need no parentheses, and a short body can follow its colon on
the same line. The enum keeps its commas, and its name after the dedent
completes the `typedef`.

## Long lines

A line break inside parentheses, brackets, or braces never ends a
statement. Outside them, a line indented deeper than the one before it
continues that line. A line that starts with `.` continues a method chain:

```x2c
#pragma indent

int main(void):
  List words = %("indentation" "groups" "blocks")
  int letters = 0
  foreach String word, words:
    letters += word.len()
  String report = %"${words.len()} words, " +
    %"$letters letters"
  List lengths = words
    .map(%!(Var word) => word.str().len())
  printf("%s: %s\n", report, lengths.str())
  return 0
```

```text
3 words, 23 letters: ( 11 6 6 )
```

## Scopes and decorators

`do:` opens a bare scope when its block is not followed by a `while` line,
which is how an indented macro keeps its temporaries to itself. A decorator
line starts with `@`, so the layout knows it wraps the next statement
rather than ending with `;`:

```x2c
#pragma indent
$(import "system-macros.xmacro")
#include <time.h>

int main(void):
  int total = 0
  do:
    int step = 2
    total += step
  @$time("sum")
  for int i = 0; i < 1000; i++:
    total += i
  printf("%d\n", total)
  return 0
```

## Converting a file

`tools/indent-convert FILE...` rewrites brace-form files in place, adding
`#pragma indent` so each keeps its name; an executable script stays
runnable by name. Every block header, including one whose body had no
braces, ends with a colon. The converter proves each conversion by
comparing the compiler's AST for the result with the original's, and it
leaves a file unchanged when they differ, as they do when indentation
misrepresents which statement an `else` or a body belongs to. `--check`
reports without writing.

A `.xpmacro` file writes macros the same way. The
[language reference](../reference/language.md#indentation-syntax) lists
every layout rule. `examples/tours/indentation.xp` is a complete program.
