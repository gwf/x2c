/* Packing directives pass through even when they surround a struct. */
#pragma pack(push, 1)
struct Packed { char tag; short value; };
#pragma pack(pop)
int main(void) { return 0; }
