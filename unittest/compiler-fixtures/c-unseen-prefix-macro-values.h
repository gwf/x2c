/* The C compiler reaches E through a computed include, which collection
   does not follow, so collection sees E with no definition. */
#define EXPORT_HEADER "c-unseen-prefix-macro-export.h"
#include EXPORT_HEADER

E int scale(int value);
E int unit;
