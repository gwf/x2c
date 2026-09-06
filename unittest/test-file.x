/*  test-file.x -- unit tests for file helpers */

#include "test-support.x"
$(import "test-macros.xmacro")
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef struct FileLockProbe {
  File file;
  int acquired;
} FileLockProbe;

static void *_file_lock_probe(void *opaque) {
  FileLockProbe *probe = opaque;
  probe.acquired = ftrylockfile(probe.file) == 0;
  if (probe.acquired) funlockfile(probe.file);
  return NULL;
}

static void _expect_file_io_error(List detail, Symbol operation, int error) {
  EXPECT_TRUE(detail.assoc(<operation>).symbol() == operation);
  EXPECT_INT_EQ(detail.assoc(Symbol.new("errno")).integer(), error);
}


static void _expect_file_read_error(List detail) {
  _expect_file_io_error(detail, <read>, EBADF);
}


static void file_write_and_readline(void) {
  File file = tmpfile();
  if (!EXPECT_NOT_NULL(file)) return;
  file.printf("value %d\n", 42);
  rewind(file);
  String line = file.readline();
  EXPECT_STR_EQ(line, "value 42\n");
  file.close();
}

static void file_string_reads_entire_file(void) {
  File file = tmpfile();
  if (!EXPECT_NOT_NULL(file)) return;
  fputs("hello\nworld", file);
  rewind(file);
  String data = file.string();
  EXPECT_STR_EQ(data, "hello\nworld");
  file.close();
}

static void file_readblock_reports_short_read_length(void) {
  File file = tmpfile();
  if (!EXPECT_NOT_NULL(file)) return;
  fputs("short-read-only", file);
  rewind(file);
  String data = file.readblock(40);
  EXPECT_STR_EQ(data, "short-read-only");
  EXPECT_INT_EQ(data.len(), 15);
  file.close();
}


static void file_rejects_invalid_text_boundaries(void) {
  $test.scoped();
  int caught = 0;

  File file = tmpfile();
  EXPECT_NOT_NULL(file);
  try file.readblock(-1);
  catch %(bad-arg *): caught++;
  file.close();

  file = tmpfile();
  EXPECT_NOT_NULL(file);
  char bytes[] = {'\0', 'x', '\n'};
  fwrite(bytes, 1, sizeof(bytes), file);
  rewind(file);
  try file.readline();
  catch %(bad-arg *): caught++;
  file.close();

  EXPECT_INT_EQ(caught, 2);
}


static void file_open_transfers_external_cause(void) {
  $test.scoped();
  const char *path = "/tmp/x2c-file-definitely-missing";
  unlink(path);
  int caught = 0;

  try File.open(path, "r");
  catch %(not-found *detail): {
    caught++;
    EXPECT_TRUE(detail.assoc(<operation>).symbol() == <open>);
    EXPECT_STR_EQ(detail.assoc(<path>).string(), path);
    EXPECT_INT_EQ(detail.assoc(Symbol.new("errno")).integer(), ENOENT);
  }

  String name = String.new(path);
  try name.open("r");
  catch %(not-found *): caught++;

  try File.fdopen(-1, "r");
  catch %(io-fail *detail): {
    caught++;
    EXPECT_TRUE(detail.assoc(<operation>).symbol() == <fdopen>);
  }

  EXPECT_INT_EQ(caught, 3);
}


static void file_empty_reads_are_canonical(void) {
  File file = tmpfile();
  if (!EXPECT_NOT_NULL(file)) return;
  EXPECT_NULL(file.readblock(0));
  EXPECT_NULL(file.string());
  file.close();
}


static void file_readline_chunk_boundaries(void) {
  int lengths[] = {511, 512, 513};
  for (int i = 0; i < 3; i++) {
    int length = lengths[i];
    char bytes[513];
    memset(bytes, 'x', length);
    bytes[length - 1] = '\n';
    File file = tmpfile();
    if (!EXPECT_NOT_NULL(file)) return;
    fwrite(bytes, 1, length, file);
    rewind(file);
    String line = file.readline();
    EXPECT_INT_EQ(line.len(), length);
    EXPECT_TRUE(line[length - 1] == '\n');
    EXPECT_NULL(file.readline());
    file.close();
  }
}


static void file_readline_final_line_without_newline(void) {
  File file = tmpfile();
  if (!EXPECT_NOT_NULL(file)) return;
  char bytes[1400];
  memset(bytes, 'z', sizeof(bytes));
  fwrite(bytes, 1, sizeof(bytes), file);
  rewind(file);
  String line = file.readline();
  EXPECT_INT_EQ(line.len(), sizeof(bytes));
  EXPECT_TRUE(line[0] == 'z');
  EXPECT_TRUE(line[sizeof(bytes) - 1] == 'z');
  EXPECT_NULL(file.readline());
  file.close();
}


static void file_string_consumes_from_current_position(void) {
  File file = tmpfile();
  if (!EXPECT_NOT_NULL(file)) return;
  fputs("prefix-rest", file);
  file.seek(7, SEEK_SET);
  EXPECT_STR_EQ(file.string(), "rest");
  file.close();
}


static void file_string_reads_pipe(void) {
  File file = File.popen("printf 'hello\\nworld'", "r");
  if (!EXPECT_NOT_NULL(file)) return;
  EXPECT_STR_EQ(file.string(), "hello\nworld");
  EXPECT_INT_EQ(file.pclose(), 0);
}


static void file_string_transfers_on_read_error(void) {
  $test.scoped();
  char path[] = "/tmp/x2c-file-error-XXXXXX";
  int descriptor = mkstemp(path);
  if (!EXPECT_TRUE(descriptor >= 0)) {
    Scope.release();
    return;
  }
  EXPECT_INT_EQ(write(descriptor, "error", 5), 5);
  EXPECT_INT_EQ(close(descriptor), 0);

  descriptor = open(path, O_WRONLY);
  unlink(path);
  if (!EXPECT_TRUE(descriptor >= 0)) {
    Scope.release();
    return;
  }
  File file = fdopen(descriptor, "w");
  if (!EXPECT_NOT_NULL(file)) {
    close(descriptor);
    Scope.release();
    return;
  }
  int caught = 0;
  try file.string();
  catch %(io-fail *detail): {
    caught++;
    _expect_file_read_error(detail);
  }
  EXPECT_TRUE(file.error());
  file.clearerr();
  try file.readblock(1);
  catch %(io-fail *detail): {
    caught++;
    _expect_file_read_error(detail);
  }
  EXPECT_TRUE(file.error());
  EXPECT_INT_EQ(caught, 2);
  file.close();
}


static void file_string_close_closes_on_transfer(void) {
  char path[] = "/tmp/x2c-file-close-error-XXXXXX";
  int descriptor = mkstemp(path);
  if (!EXPECT_TRUE(descriptor >= 0)) return;
  EXPECT_INT_EQ(close(descriptor), 0);

  descriptor = open(path, O_WRONLY);
  unlink(path);
  if (!EXPECT_TRUE(descriptor >= 0)) return;
  File file = fdopen(descriptor, "w");
  if (!EXPECT_NOT_NULL(file)) {
    close(descriptor);
    return;
  }
  int caught = 0;
  try file.string_close();
  catch %(io-fail *): caught = 1;
  EXPECT_TRUE(caught);
  errno = 0;
  EXPECT_INT_EQ(fcntl(descriptor, F_GETFD), -1);
  EXPECT_INT_EQ(errno, EBADF);
}


static void file_raw_line_status_preserves_bytes(void) {
  File file = tmpfile();
  if (!EXPECT_NOT_NULL(file)) return;
  unsigned char bytes[] = {'a', '\0', 'b', '\n'};
  fwrite(bytes, 1, sizeof(bytes), file);
  rewind(file);
  Block line = Block.new(sizeof(char));
  EXPECT_INT_EQ(file.readline_into(line), FILE_READ_DATA);
  EXPECT_INT_EQ(line.length, sizeof(bytes));
  EXPECT_TRUE(memcmp(line.bytes, bytes, sizeof(bytes)) == 0);
  EXPECT_INT_EQ(file.readline_into(line), FILE_READ_EOF);
  EXPECT_INT_EQ(line.length, 0);
  line.free();
  file.close();
}

static void file_raw_line_unlocks_during_error_cleanup(void) {
  File file = tmpfile();
  if (!EXPECT_NOT_NULL(file)) return;
  Block line = Block.new(1);
  int descriptor = file.fileno();
  EXPECT_INT_EQ(close(descriptor), 0);
  int caught = 0;
  try file.readline_into(line);
  catch %(io-fail *): caught = 1;
  EXPECT_TRUE(caught);

  FileLockProbe probe = { .file = file };
  pthread_t thread;
  int created = pthread_create(&thread, NULL, _file_lock_probe, &probe);
  EXPECT_INT_EQ(created, 0);
  if (!created) EXPECT_INT_EQ(pthread_join(thread, NULL), 0);
  EXPECT_TRUE(probe.acquired);

  line.free();
  file.close();
}

static void file_raw_reads_transfer_host_failures(void) {
  $test.scoped();
  File file = tmpfile();
  if (!EXPECT_NOT_NULL(file)) {
    Scope.release();
    return;
  }
  Block line = Block.new(sizeof(char));
  int descriptor = file.fileno();
  EXPECT_INT_EQ(close(descriptor), 0);
  int caught = 0;
  try file.readline_into(line);
  catch %(io-fail *detail): {
    caught++;
    _expect_file_read_error(detail);
  }
  EXPECT_TRUE(file.error());
  file.clearerr();
  try file.read_into(line);
  catch %(io-fail *detail): {
    caught++;
    _expect_file_read_error(detail);
  }
  EXPECT_TRUE(file.error());
  EXPECT_INT_EQ(caught, 2);
  line.free();
  file.close();
}


static void file_raw_read_and_write_all(void) {
  File file = tmpfile();
  if (!EXPECT_NOT_NULL(file)) return;
  unsigned char bytes[] = {'a', '\0', 'b', '\n', 'c'};
  EXPECT_TRUE(file.write_all(bytes, sizeof(bytes)));
  EXPECT_TRUE(file.write_all(NULL, 0));
  EXPECT_FALSE(file.write_all(NULL, 1));
  rewind(file);
  Block content = Block.new(sizeof(char));
  EXPECT_INT_EQ(file.read_into(content), FILE_READ_DATA);
  EXPECT_INT_EQ(content.length, sizeof(bytes));
  EXPECT_TRUE(memcmp(content.bytes, bytes, sizeof(bytes)) == 0);
  EXPECT_INT_EQ(file.read_into(content), FILE_READ_EOF);
  Block invalid = Block.new(sizeof(long));
  EXPECT_INT_EQ(file.read_into(invalid), FILE_READ_ERROR);
  EXPECT_INT_EQ(file.readline_into(invalid), FILE_READ_ERROR);
  invalid.free();
  content.free();
  file.close();
}


static void file_write_failures_raise_io_error(void) {
  Scope.retain();
  defer Scope.release();
  unsigned char byte = 'x';

  File output = tmpfile();
  if (!EXPECT_NOT_NULL(output)) return;
  defer output.close();
  output.setbuf(NULL);
  int descriptor = output.fileno();
  if (!EXPECT_INT_EQ(close(descriptor), 0)) return;
  int caught = 0;
  try output.write_all(&byte, 1);
  catch %(io-fail *detail): {
    caught++;
    _expect_file_io_error(detail, <write>, EBADF);
  }

  File source = tmpfile();
  if (!EXPECT_NOT_NULL(source)) return;
  defer source.close();
  File copy_output = tmpfile();
  if (!EXPECT_NOT_NULL(copy_output)) return;
  defer copy_output.close();
  EXPECT_INT_EQ(fwrite(&byte, 1, 1, source), 1);
  rewind(source);
  copy_output.setbuf(NULL);
  descriptor = copy_output.fileno();
  if (!EXPECT_INT_EQ(close(descriptor), 0)) return;
  size_t copied = 1;
  try source.copy_to(copy_output, &copied);
  catch %(io-fail *detail): {
    caught++;
    _expect_file_io_error(detail, <write>, EBADF);
  }
  // The transfer still leaves the completed byte count behind for the catch.
  EXPECT_INT_EQ(copied, 0);
  EXPECT_INT_EQ(caught, 2);
}


static void file_copy_to_reports_progress(void) {
  File source = tmpfile(), output = tmpfile();
  if (!EXPECT_NOT_NULL(source) || !EXPECT_NOT_NULL(output)) return;
  unsigned char bytes[4097];
  for (size_t i = 0; i < sizeof(bytes); i++) bytes[i] = i % 251;
  fwrite(bytes, 1, sizeof(bytes), source);
  rewind(source);
  size_t copied = 0;
  EXPECT_TRUE(source.copy_to(output, &copied));
  EXPECT_INT_EQ(copied, sizeof(bytes));
  rewind(output);
  Block content = Block.new(sizeof(char));
  EXPECT_INT_EQ(output.read_into(content), FILE_READ_DATA);
  EXPECT_INT_EQ(content.length, sizeof(bytes));
  EXPECT_TRUE(memcmp(content.bytes, bytes, sizeof(bytes)) == 0);
  EXPECT_FALSE(source.copy_to(NULL, &copied));
  EXPECT_INT_EQ(copied, 0);
  content.free();
  source.close();
  output.close();
}

static void file_iterator_reads_lines(void) {
  $test.scoped();
  File file = tmpfile();
  if (!EXPECT_NOT_NULL(file)) {
    Scope.release();
    return;
  }
  fputs("alpha\nbeta\n", file);
  rewind(file);
  struct Iter lines_storage;
  Iter lines = file.iter(&lines_storage);
  Var first = lines.next();
  EXPECT_STR_EQ(first.string(), "alpha\n");
  Var second = lines.next();
  EXPECT_STR_EQ(second.string(), "beta\n");
  EXPECT_TRUE(lines.next() is void);
  Var exhausted;
  EXPECT_FALSE(lines.try_next(&exhausted));
  file.close();
}


static void file_iterator_releases_line_on_transfer(void) {
  $test.scoped();
  File file = tmpfile();
  if (!EXPECT_NOT_NULL(file)) {
    Scope.release();
    return;
  }
  struct Iter lines_storage;
  Iter lines = file.iter(&lines_storage);
  int descriptor = file.fileno();
  EXPECT_INT_EQ(close(descriptor), 0);
  int caught = 0;
  try lines.next();
  catch %(io-fail *): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_TRUE(lines.state is void);
  file.close();
}


static void file_var_dispatches_existing_methods(void) {
  $test.scoped();
  File file = tmpfile();
  if (!EXPECT_NOT_NULL(file)) {
    Scope.release();
    return;
  }
  fputs("boxed\n", file);
  rewind(file);
  Var boxed = file;

  EXPECT_TRUE(boxed is <file>);
  EXPECT_INT_EQ(boxed.hash(), file.hash());
  EXPECT_TRUE(boxed.repr().startswith(%"<File:"));
  EXPECT_STR_EQ(boxed.str(), "boxed\n");

  rewind(file);
  struct Iter lines_storage;
  Iter lines = boxed.iter(&lines_storage);
  EXPECT_STR_EQ(lines.next().string(), "boxed\n");
  EXPECT_TRUE(lines.next() is void);

  file.close();
}

static void file_identity_is_handle_based(void) {
  $test.scoped();
  File first = tmpfile(), second = tmpfile();
  if (!EXPECT_NOT_NULL(first) || !EXPECT_NOT_NULL(second)) {
    if (first) first.close();
    if (second) second.close();
    Scope.release();
    return;
  }
  File alias = first;
  EXPECT_TRUE(first == alias);
  EXPECT_FALSE(first == second);
  EXPECT_INT_EQ(first.hash(), alias.hash());

  Var boxed = first, boxed_alias = alias, boxed_second = second;
  EXPECT_TRUE(boxed == boxed_alias);
  EXPECT_FALSE(boxed == boxed_second);
  EXPECT_INT_EQ(boxed.compare(boxed_alias), 0);
  EXPECT_TRUE(boxed.compare(boxed_second) != 0);
  EXPECT_INT_EQ(boxed.hash(), first.hash());

  File no_file = NULL;
  EXPECT_TRUE(no_file == NULL);
  EXPECT_INT_EQ(no_file.hash(), Var.new(<p48>, NULL).hash());
  Var boxed_null = Var.new(<file>, NULL);
  EXPECT_INT_EQ(boxed_null.compare(boxed_null), 0);
  EXPECT_TRUE(boxed_null.hash() != 0);

  first.close();
  second.close();
}


void file_suite(void) {
  $test.run(file_write_and_readline);
  $test.run(file_string_reads_entire_file);
  $test.run(file_readblock_reports_short_read_length);
  $test.run(file_rejects_invalid_text_boundaries);
  $test.run(file_open_transfers_external_cause);
  $test.run(file_empty_reads_are_canonical);
  $test.run(file_readline_chunk_boundaries);
  $test.run(file_readline_final_line_without_newline);
  $test.run(file_string_consumes_from_current_position);
  $test.run(file_string_reads_pipe);
  $test.run(file_string_transfers_on_read_error);
  $test.run(file_string_close_closes_on_transfer);
  $test.run(file_raw_line_status_preserves_bytes);
  $test.run(file_raw_line_unlocks_during_error_cleanup);
  $test.run(file_raw_reads_transfer_host_failures);
  $test.run(file_raw_read_and_write_all);
  $test.run(file_write_failures_raise_io_error);
  $test.run(file_copy_to_reports_progress);
  $test.run(file_iterator_reads_lines);
  $test.run(file_iterator_releases_line_on_transfer);
  $test.run(file_var_dispatches_existing_methods);
  $test.run(file_identity_is_handle_based);
}
