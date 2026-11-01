#include <stdio.h>

#define volatile changed
#define short int

int main(void) {
  List words = %(WORD volatile short $(sizeof(short)));
  Array values = %[WORD volatile short];
  SymbolSet members = %<WORD volatile short>;
  printf("%d %d %d %d\n", words.car() == <WORD>,
    words.cadr() == <volatile>, words.caddr() == <short>,
    words[3] == sizeof(int));
  printf("%d %d\n", values[0] == <WORD>, values[1] == <volatile>);
  printf("%d %d\n", members.contains(<WORD>), members.contains(<volatile>));
  return 0;
}
