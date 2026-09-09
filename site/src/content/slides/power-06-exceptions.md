---
section: power
tab: exceptions
---

```x2c
~#include <assert.h>
~#include <fcntl.h>
~#include <errno.h>
~static int opened_fd = -1;
// Close the file on success or while unwinding from a failed read.
String read_text(String path) {
  File input = path.open("r");
~opened_fd = input.fileno();
  defer input.close();
  return input.string();
}

// The caller decides how to present content that cannot be text.
String preview(String path) {
  try return read_text(path);
  catch %(bad-arg *):
~{
~assert(fcntl(opened_fd, F_GETFD) == -1 && errno == EBADF);
    return "No text preview: file contains a NUL byte.";
~}
  catch %(not-found *):
    return "No preview: file not found.";
  catch:
    return "No preview: unable to read file.";
}

~int main(int argc, char **argv) {
String directory = argc > 1 ? argv[1]
                           : "examples/data/power-exceptions";
~assert(preview(%"$directory/document.txt") == %"Meeting at noon.");
~assert(fcntl(opened_fd, F_GETFD) == -1 && errno == EBADF);
// document.bin contains a NUL byte, which String cannot hold.
puts(preview(%"$directory/document.bin"));
~assert(fcntl(opened_fd, F_GETFD) == -1 && errno == EBADF);
~assert(preview(%"$directory/missing-preview-file.txt")
~       == %"No preview: file not found.");
~assert(preview(directory) == %"No preview: unable to read file.");
~assert(fcntl(opened_fd, F_GETFD) == -1 && errno == EBADF);
~return 0;
~}
```

`File.string` rejects embedded NUL bytes. A deferred `File.close` runs
before `preview` handles that failure. Named `catch` clauses distinguish
invalid text from a missing file; `catch:` handles other failures. The
loader owns cleanup, while its caller chooses how to recover.
