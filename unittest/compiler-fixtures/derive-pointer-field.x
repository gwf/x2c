#include "derive.x"
typedef struct Bad { int *raw; } Bad;
$derive(Bad, <map>);
