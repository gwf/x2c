/* symbols.x -- exercise simple and quoted symbol literals */

#include <stdio.h>


int main(void) {
  Symbol simple = <demo>;
  Symbol repeated = <demo>;
  Symbol quoted = <"->">;
  Symbol seven_bit = <"Token@!">;
  Map config = %{host: "localhost", port: 8080};

  printf("simple: %s\n", simple.str());
  printf("quoted: %s\n", quoted.str());
  printf("same: %s\n", simple == repeated ? "yes" : "no");
  printf("seven-bit: %s (%d)\n", seven_bit.str(), seven_bit.len());
  printf("map: %s:%d\n", config[<host>].string(), config[<port>].int());

  return 0;
}
