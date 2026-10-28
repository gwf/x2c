#include "derive.x"
typedef struct Point { int x, y; } Point;
typedef struct Bad { Point home; } Bad;
$derive(Point, <map>);
$derive(Bad, <args>);
