/* Distinct callback results prove each indexed interception point fires. */
#include "component.x"

typedef struct Indexed { int value; } Indexed;
int Indexed.getindex(Indexed value, int key) { (void) key; return value.value; }
int Indexed.setindex(Indexed value, int key, int next) {
  (void) value; (void) key; return next;
}

$rewrite($at, $!Indexed{${%(!and ?base)}}, <?key>)
meta Code probe_read(Code code) { (void) code; return $!int{101}; }
$rewrite($put, $!Indexed{${%(!and ?base)}}, <?key>, <?value>)
meta Code probe_store(Code code) { (void) code; return $!int{102}; }
$rewrite($add_at, $!Indexed{${%(!and ?base)}}, <?key>, <?value>)
meta Code probe_update(Code code) { (void) code; return $!int{103}; }
$rewrite($before_at, $!Indexed{${%(!and ?base)}}, <?key>)
meta Code probe_prefix(Code code) { (void) code; return $!int{104}; }
$rewrite($after_at, $!Indexed{${%(!and ?base)}}, <?key>)
meta Code probe_postfix(Code code) { (void) code; return $!int{105}; }

int main(void) {
  Indexed value = {7};
  int read = value[0], stored = (value[0] = 8), updated = (value[0] += 2);
  int prefix = ++value[0], postfix = value[0]++;
  int ordinary[1] = {9};
  printf("hooks: %d %d %d %d %d ordinary: %d\n",
    read, stored, updated, prefix, postfix, ordinary[0]);
  return read != 101 || stored != 102 || updated != 103 || prefix != 104 ||
    postfix != 105 || ordinary[0] != 9;
}
