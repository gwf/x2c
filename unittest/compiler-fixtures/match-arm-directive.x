#include <stdio.h>
#define ON

static void arms(List subject) {
  Symbol wanted = <w>;
  match (subject) {
#ifdef OFF
    case %(foo 1): puts("off foo");
    case %(?): puts("off any");
#endif
    case %(1): puts("one");
#ifdef ON
    case %(2): puts("two");
#endif
#ifdef OFF
    case %(3): puts("off three");
#else
    case %(3): puts("three");
#endif
    case %(big ?n) if (Var_int(n) > 5): puts("big");
#ifndef ON
    case %(foo ?n): printf("off foo %d\n", Var_int(n));
#else
    case %(foo (bar ?n)): printf("foo bar %d\n", Var_int(n));
#endif
    case %(foo *): puts("foo");
#ifdef ON
    case %(sym): puts("sym");
#endif
#ifdef OFF
    case %(off): puts("off sym");
#endif
    case %($wanted *): puts("wanted");
#if defined(OFF)
    default: puts("off other");
#endif
  }
}

static void defaults(List subject) {
  match (subject) {
    case %(1): puts("default one");
#ifdef ON
    default: puts("default on");
#elif defined(OFF)
    case %(2): puts("default off two");
# ifdef OFF
    default: puts("default off");
# else
    default: puts("default neither");
# endif
#endif
  }
}

int main(void) {
  foreach (List subject, %((1) (2) (3) (foo 1) (foo (bar 4)) (big 9) (big 1)
                           (sym) (off) (w 1) (other)))
    arms(subject);
  foreach (Var item, %((2) (off)))
    match (item) {
#ifdef OFF
      case %(2): puts("loop off two");
#endif
      case %(2): puts("loop two");
#ifdef OFF
      default: puts("loop off");
#endif
    }
  foreach (List subject, %((1) (2))) defaults(subject);
  return 0;
}
