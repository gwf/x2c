#include <stdio.h>

#define volatile changed
#define short int

int main(void) {
  List words = %(word volatile short $(sizeof(short)));
  Array values = %[word, volatile, short];
  SymbolSet members = %<word volatile short>;
  printf("%d %d %d %d\n", words.car() == <word>,
    words.cadr() == <volatile>, words.caddr() == <short>,
    words[3] == sizeof(int));
  printf("%d %d\n", values[0] == <word>, values[1] == <volatile>);
  printf("%d %d\n", members.contains(<word>), members.contains(<volatile>));
  return 0;
}
