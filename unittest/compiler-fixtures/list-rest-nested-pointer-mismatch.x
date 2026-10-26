#include "lib.x"
typedef int (*Ordinary)(List);
typedef int (*Rest)(....);
int ordinary(List items) => items.len();
int invoke_rest(Rest callback) { return callback(%(1 2)); }
int main(void) {
 int (*invoke_ordinary)(Ordinary) = invoke_rest;
 printf("%d\n", invoke_ordinary(ordinary));
 return 0;
}
