#pragma pack(push, 1)
struct HeaderPragma { char tag; short value; };
#pragma pack(pop)

struct HeaderPacked { char tag; short value; } __attribute__((packed));

struct HeaderAligned { char tag; short value __attribute__((aligned(8))); };

int header_value(int value) __attribute__((warn_unused_result));

struct HeaderPlain { char tag; short value; };
