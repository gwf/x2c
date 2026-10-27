#include "lib.x"
int count(int prefix, List @items) => prefix + items.len();
int main(void) { return count(); }
