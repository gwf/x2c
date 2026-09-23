#pragma pack(push, 1)
struct HeaderPragma { char tag; short value; };
#pragma pack(pop)

struct HeaderPacked { char tag; short value; } __attribute__((packed));

struct HeaderAligned { char tag; short value __attribute__((aligned(8))); };

void *header_buffer(void) __attribute__((assume_aligned(16)));

struct HeaderPlain { char tag; short value; } __attribute__((__unused__));
