#include "playground.h"

int repl_test_packet(void *address) {
  PlaygroundPacket (*make)(unsigned char, int) =
    (PlaygroundPacket (*)(unsigned char, int)) address;
  PlaygroundPacket packet = make(7, 1234);
  return sizeof(packet) != 5 || packet.marker != 7 || packet.value != 1234;
}
