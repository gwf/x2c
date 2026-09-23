#define DEPRECATED(message) __attribute__((deprecated(message)))

struct Trailing { int value; } __attribute__((deprecated("use f(x), \")")));
struct __attribute__((deprecated(")"))) Leading { int value; };
struct Opening { int value; } __attribute__((deprecated("(")));
typedef struct Named { int value; } __attribute__((aligned(4))) Named;
enum __attribute__((deprecated("a, b"))) Mode { MODE_ON } DEPRECATED("x");
union DEPRECATED("x") Tagged { int value; } DEPRECATED("y");

struct Aligned { char tag; } __attribute__((aligned(8)));

static inline int aligned_size(void) { return sizeof(struct Aligned); }
