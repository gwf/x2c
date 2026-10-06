#include "x2c.x"

static int barrier(int Chain) => Chain;
static typedef struct Holder { int Chain; char label[sizeof("Chain")]; } Holder;
static typedef struct Chain { int n; } ChainBase;
static typedef struct Chain ChainOther;
static typedef ChainBase Chain;
static typedef const Chain QualifiedChain;
static typedef union Choice { int n; } ChoiceBase;
static typedef ChoiceBase Choice;
static typedef enum Shade { LIGHT, DARK } ShadeBase;
static typedef ShadeBase Shade;
static typedef Chain (*ReadChain)(QualifiedChain);
static typedef ReadChain (*ReadFactory)(void);

static Chain read_chain(QualifiedChain value) => value;
static ReadChain read_factory(void) => read_chain;

int main(void) {
  ChainOther other = {3};
  Choice choice = {4};
  Shade shade = DARK;
  ReadFactory factory = read_factory;
  return factory()(other).n == 3 && choice.n == 4 && shade == DARK ? 0 : 1;
}
