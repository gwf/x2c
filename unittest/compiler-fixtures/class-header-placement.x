class Box struct { int v; } *;
typedef struct After { int w; } After;
typedef struct Uses { After a; } *Uses;

int Box.twice(Box box) { return box.v * 2; }

typedef struct Hidden { int h; } Hidden;
