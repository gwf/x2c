#ifndef REPL_PLAYGROUND_H
#define REPL_PLAYGROUND_H

typedef struct PlaygroundPoint { int x; int y; } PlaygroundPoint;
typedef struct __attribute__((packed)) PlaygroundPacket {
  unsigned char marker;
  int value;
} PlaygroundPacket;
typedef struct PlaygroundHandle PlaygroundHandle;

enum PlaygroundAxis { PLAYGROUND_X = 1, PLAYGROUND_Y = 2 };
#define PLAYGROUND_SCALE 3

extern int playground_calls;
/** Allocates a point with the two requested coordinates. */
PlaygroundPoint *playground_new(int x, int y);
void playground_move(PlaygroundPoint *point, int dx);
void playground_free(PlaygroundPoint *point);
PlaygroundPoint playground_value(int x, int y);
PlaygroundPacket playground_packet(unsigned char marker, int value);
int playground_apply(PlaygroundPoint *point, int (*combine)(int, int));
PlaygroundHandle *playground_open(int value);
int playground_read(PlaygroundHandle *handle);
void playground_close(PlaygroundHandle *handle);

#endif
