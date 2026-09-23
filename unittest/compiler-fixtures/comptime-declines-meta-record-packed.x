/* Packing is rejected even when push and pop would balance. */
#pragma pack(push, 1)
struct Packed { char tag; short value; };
#pragma pack(pop)
int main(void) { return 0; }
