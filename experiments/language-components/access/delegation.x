/* Missing Wrapper methods forward through the same pattern registry. */
#pragma once
#include "rewrite.x"

macro Expression $member_call(Expr $receiver, Name $member, Expr @arguments) =>
  $receiver.$member(@arguments);

typedef struct Reader { int value; } Reader;
typedef struct Wrapper { Reader part; } Wrapper;
int Reader.read(Reader reader, int add) => reader.value + add;
void Reader.bump(Reader &reader, int add) { reader.value += add; }
int Wrapper.own(Wrapper wrapper) => 100 + wrapper.part.value;

typedef struct Unrelated { int value; } Unrelated;
int Unrelated.read(Unrelated value, int add) { (void) value; return 997 + add; }

$rewrite($member_call, $!Wrapper{${%(!and ?receiver)}}, <?member>, <*arguments>)
meta Code forward_reader(Code code) {
  match (code) case $member_call(?receiver, ?member, *arguments):
    return $!($receiver.part.$member(@arguments));
  return code;
}
