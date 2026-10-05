#include "x2c.x"

#pragma private
static int barrier(int Chain) => Chain;
typedef struct Holder { int Chain; char label[sizeof("Chain")]; } Holder;
typedef struct Chain { int n; } ChainBase;
typedef struct Chain ChainOther;
typedef ChainBase Chain;
typedef const Chain QualifiedChain;
typedef union Choice { int n; } ChoiceBase;
typedef ChoiceBase Choice;
typedef enum Shade { LIGHT, DARK } ShadeBase;
typedef ShadeBase Shade;
typedef Chain (*ReadChain)(QualifiedChain);
typedef ReadChain (*ReadFactory)(void);

static Chain read_chain(QualifiedChain value) => value;
static ReadChain read_factory(void) => read_chain;

int main(void) {
  ChainOther other = {3};
  Choice choice = {4};
  Shade shade = DARK;
  ReadFactory factory = read_factory;
  return factory()(other).n == 3 && choice.n == 4 && shade == DARK ? 0 : 1;
}
