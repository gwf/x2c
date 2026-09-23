/* A packed attribute in a macro body is rejected at its definition. */
#define PACKED __attribute__((packed))
struct HeaderMacro { char tag; short value; } PACKED;
int main(void) { return 0; }
