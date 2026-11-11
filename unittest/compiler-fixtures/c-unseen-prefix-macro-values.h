/* The C compiler reaches E through a computed include, which collection
   does not follow, so collection sees E with no definition. */
#define EXPORT_HEADER "c-unseen-prefix-macro-export.h"
#include EXPORT_HEADER
#include <stdbool.h>

E int scale(int value);
E int unit;

/* A second name that a declarator follows is the type, whether collection
   knows it, as Point, or not, as bool. E is again a prefix. */
typedef struct Point { int x; } Point;
E Point origin(void);
E Point *nearest(Point *from);
E bool positive(int value);
