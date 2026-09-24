/* A packed attribute is rejected when its macro marks a parsed struct. */
#define PACKED __attribute__((packed))
struct HeaderMacro { char tag; short value; } PACKED;
int main(void) { return 0; }
