#include "x2c.x"
#include <assert.h>

int main(void) {
  List pair = %(2 3), empty = NULL;
  assert(!List.new());
  assert(List.new(1, 2, 3) == %(1 2 3));
  assert(List.new(pair) == %($pair));
  assert(List.new(1, @pair, @empty, 4) == %(1 2 3 4));
  assert(List.new(1, @pair, @(empty), 4) == $(1, @pair, @(empty), 4));
  assert(List.new(pair) == $(pair));
  assert(List.new() == $());
  List (*constructor)(List @) = List.new;
  Func dynamic = List.new;
  assert(constructor(pair) == %($pair));
  assert(dynamic(1, @pair, 4).list() == %(1 2 3 4));
  assert(dynamic(1, @(pair), 4).list() == $(1, @(pair), 4));
  puts("named List construction ok");
  return 0;
}
