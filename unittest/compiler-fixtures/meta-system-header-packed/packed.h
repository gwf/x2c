#pragma pack(push, 1)
struct HeaderPragma { char tag; short value; };
#pragma pack(pop)

struct HeaderPacked { char tag; short value; } __attribute__((packed));

struct HeaderAligned { char tag; short value __attribute__((aligned(8))); };

void *header_buffer(void) __attribute__((assume_aligned(16)));

struct HeaderPlain { char tag; short value; } __attribute__((__unused__));

enum HeaderSmall { HEADER_SMALL } __attribute__((packed));
enum __attribute__((packed)) HeaderLead { HEADER_LEAD };
struct HeaderSmallField { enum HeaderSmall small; };
struct HeaderLeadField { enum HeaderLead lead; };

#define HEADER_PACKED __attribute__((packed))
#define HEADER_PACKED_BY(n) __attribute__((packed))
struct HeaderMacro { char tag; short value; } HEADER_PACKED;
struct HeaderMacroBy { char tag; short value; } HEADER_PACKED_BY(1);

#if defined(__GNUC__)
#define HEADER_PACKED_IF __attribute__((packed))
#else
#define HEADER_PACKED_IF
#endif
struct HeaderMacroIf { char tag; short value; } HEADER_PACKED_IF;

#define HEADER_EMPTY
#define HEADER_MARKED __attribute__((deprecated))
#define HEADER_EXPORT __attribute__((visibility("default")))
struct HeaderEmpty { char tag; short value; } HEADER_EMPTY;
struct HeaderMarked { char tag; short value; } HEADER_MARKED;
struct HEADER_EXPORT HeaderExport { char tag; short value; };
