#include "lib.x"
typedef int (*Ordinary)(List);
typedef int (*Rest)(List @);
int invoke(Rest callback);
int invoke(Ordinary callback) { return callback(%(1 2)); }
