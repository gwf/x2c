#include "lib.x"
int count(List @items) => items.len();
int (*ordinary)(List) = count;
