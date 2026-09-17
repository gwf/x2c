/*  A Var has no fixed tag for an enum, so a class cannot take an enum value
    representation. Naming the enum's typedef is the spelling that works, and
    the rejection has to say so rather than blame an enumerator. */
#include "x2c.x"

typedef enum Shade { LIGHT, DARK } Shade;

class Tone Shade;

class Color enum { RED, GREEN };

int main(void) { return Tone.new(LIGHT) == LIGHT ? 0 : 1; }
