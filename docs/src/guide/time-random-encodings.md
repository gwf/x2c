# Time, Random Values, and Encodings

Four optional modules cover clocks, random values, and the text forms that
protocols and file formats use. Include the ones a file uses:

```x2c
#include "time.x"
#include "random.x"
#include "encoding.x"
#include "url.x"
```

`url.x` includes `encoding.x`. Each module raises the shared
[Error causes](exceptions.md): `<malformed>` for text it cannot read, with
`reason` and byte `offset` details, `<conv-range>` for a time outside the
64-bit range, and `<bad-arg>` for an invalid argument.

## Durations and clocks

A `Duration` is a signed count of nanoseconds, and a `Time` is an instant
counted in nanoseconds from the Unix epoch. Both are value classes, so they
copy like numbers, box into a `Var`, and work as `Map` keys. Durations add
and subtract with `+` and `-`, and both types compare with `<` and `==`.
Interpolation prints a Duration in the units Go uses:

```x2c
~#include "time.x"
~int main(void) {
Duration timeout = Duration.seconds(1.5), step = Duration.milliseconds(250);
Duration left = timeout - step;
puts(%"$left left; four steps take $(step.scale(4))");
printf("%d %lld\n", step < timeout, left.total_milliseconds());
~  return 0;
~}
```

```text
1.25s left; four steps take 1s
1 1250
```

`Time.now` reads the wall clock, which moves when the system time is set.
`Time.monotonic` reads a clock that never decreases, as a Duration since an
unspecified start, so the difference of two readings measures elapsed time.
`Time.sleep` waits at least the Duration it is given:

```x2c
~#include "time.x"
~int main(void) {
Duration start = Time.monotonic();
Time.sleep(Duration.milliseconds(20));
Duration elapsed = Time.monotonic() - start;
fprintf(stderr, "slept %s at %s\n", elapsed.str(), Time.now().str());
~  return elapsed >= Duration.milliseconds(20) ? 0 : 1;
~}
```

## Calendar time

`Time.parse` reads an RFC 3339 timestamp, the profile of ISO 8601 that
network protocols use, and `Time.str` writes one in UTC. `Time.format`
applies C's `strftime` conversions in UTC, and `Time.utc` returns the
calendar fields as a `DateTime`:

```x2c
~#include "time.x"
~int main(void) {
Time launch = Time.parse("2026-10-28T10:05:09-04:00");
puts(%"$launch");
puts(launch.format("%A %d %B %Y, %H:%M UTC"));
DateTime day = launch.utc();
printf("%d-%02d-%02d is weekday %d\n", day.year, day.month, day.day,
       day.weekday());
Time later = launch.plus(Duration.seconds(36 * 3600));
puts(%"$(later.since(launch)) later it is $later");
~  return 0;
~}
```

```text
2026-10-28T14:05:09Z
Wednesday 28 October 2026, 14:05 UTC
2026-10-28 is weekday 3
36h0m0s later it is 2026-10-30T02:05:09Z
```

`Time.local` and `Time.format_local` use the C library's local zone, which
the `TZ` environment variable selects; there is no time zone database
beyond what the C library reads. A `DateTime` converts to the `Time` its
fields name wherever a `Time` is expected, and its fields need not be
normalized, so day 32 of January is February 1. `strftime` names days and
months in the current C locale, which is English unless the program calls
`setlocale`.

## Random values

`Random` is a seedable xoshiro256** generator. The same seed always yields
the same sequence, which makes simulations and tests repeatable. A
`Random` is a value: a copy continues the same sequence on its own.
`below(n)` draws an integer from 0 through `n - 1` without bias,
`double` draws from [0, 1), and `shuffle` and `choice` work on an `Array`:

```x2c
~#include "random.x"
~int main(void) {
Random r = Random.new(42);
long die = r.below(6) + 1;
Array deck = ["ace", "king", "queen", "jack"];
r.shuffle(deck);
printf("%ld %s %s\n", die, deck.repr(), r.choice(deck).str());
~  return 0;
~}
```

```text
1 [ "ace", "king", "jack", "queen" ] ace
```

A `Random` is fast and predictable from its output, so it must not make
secrets. `Random.secure_fill` fills a buffer from the operating system's
cryptographic generator, and `Random.from_entropy` seeds a `Random` from it
when the sequence should differ on every run. `Uuid.v4` returns a random
UUID in its canonical lowercase form, and `Uuid.parse` checks and
normalizes one:

```x2c
~#include "random.x"
~int main(void) {
unsigned char key[32];
Random.secure_fill(key, sizeof key);
String id = Uuid.v4();
puts(Uuid.parse("9F6E2C1A-0B7D-4E3F-A2C5-6D8E9F0A1B2C"));
~  return Uuid.is_valid(id) ? 0 : 1;
~}
```

```text
9f6e2c1a-0b7d-4e3f-a2c5-6d8e9f0a1b2c
```

## Text encodings

`String` operations work on bytes. `encoding.x` reads and writes the
Unicode code points that UTF-8 bytes encode. `String.code_points` yields
each one as an `int`, `String.code_point_count` counts them, and
`Buffer.write_code_point` appends one:

```x2c
~#include "encoding.x"
~int main(void) {
String word = "na\xc3\xafve";
printf("%d bytes, %d code points\n", word.len(), word.code_point_count());
foreach (int point in word.code_points()) printf(" U+%04X", point);
Buffer out = auto Buffer.new(0);
out.write_code_point(0x263A);
printf("\n%s %d\n", out.str().hex_encode(), "\xc0\x80".is_utf8());
~  return 0;
~}
```

```text
6 bytes, 5 code points
 U+006E U+0061 U+00EF U+0076 U+0065
e298ba 0
```

Ill-formed UTF-8 raises `<malformed>` at the offset of the first bad byte.

Base64, hexadecimal, and percent-encoding turn bytes into ASCII text and
back. Each decoder checks its input and raises `<malformed>` with the
offset where decoding stopped. A `String` cannot hold a NUL byte, so the
decoders that return text reject one; the `_bytes` forms return a `Block`
of bytes instead, and the `Block` encoders take one:

```x2c
~#include "encoding.x"
~int main(void) {
puts("hello, world".base64_encode());
puts("aGVsbG8sIHdvcmxk".base64_decode());
puts("\xfb\xff".base64url_encode());
puts("x2c".hex_encode());
puts("a b&c".percent_encode());
Block bytes = "AAEC/w==".base64_decode_bytes();
puts(bytes.hex_encode());
~  return 0;
~}
```

```text
aGVsbG8sIHdvcmxk
hello, world
-_8
783263
a%20b%26c
000102ff
```

## URLs and query strings

`Url.parse` splits a URL, or a relative reference such as an HTTP request
target, into its RFC 3986 components. Each component keeps its
percent-encoding, and `Url.str` joins them again. `Url.parse_query` reads a
query string into a `Map`, decoding `+` as a space as HTML forms do, and
`Url.format_query` writes one from a `Map`:

```x2c
~#include "url.x"
~int main(void) {
Url url = Url.parse("https://example.com:8443/docs/a%20b?q=two+words&page=2");
printf("%s %s %d %s\n", url.scheme, url.host, url.port,
       url.path.percent_decode());
Map query = Url.parse_query(url.query);
printf("%s\n", query["q"]);
url.query = Url.format_query({"q": "x&y", "page": 3});
puts(url.str());
~  return 0;
~}
```

```text
https example.com 8443 /docs/a b
two words
https://example.com:8443/docs/a%20b?page=3&q=x%26y
```

The empty `String` is the null pointer, so an empty query or fragment is
the same as an absent one. A port the URL does not name is 0.
