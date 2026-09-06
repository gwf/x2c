/*  test-fs.x -- asynchronous filesystem results and lifetimes */

import "libuv" with UvFile, UvFs, UvLoop, UvStat;

#include "test-support.x"
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

$(import "../../../unittest/test-macros.xmacro")

static String _fs_path(String name) {
  int pid = (int) getpid();
  return %"/tmp/x2c-libuv-fs-$pid-$name";
}

typedef struct OffsetState {
  UvFile file;
  Bytes read;
  uv_thread_t driver;
  int callback_thread;
  int open_calls;
  int write_calls;
  int read_calls;
  int close_calls;
} OffsetState;

static void _offset_closed(UvFs request, Var value) {
  OffsetState *state = value.pointer();
  uv_thread_t current = uv_thread_self();
  state.callback_thread &= uv_thread_equal(&state.driver, &current);
  state.close_calls++;
  EXPECT_INT_EQ(request.operation(), UV_FS_CLOSE);
  EXPECT_INT_EQ(request.result(), 0);
  EXPECT_NULL(request.native()->path);
}

static void _offset_read(UvFs request, Var value) {
  OffsetState *state = value.pointer();
  uv_thread_t current = uv_thread_self();
  state.callback_thread &= uv_thread_equal(&state.driver, &current);
  state.read_calls++;
  state.read = request;
  EXPECT_INT_EQ(request.operation(), UV_FS_READ);
  EXPECT_INT_EQ(request.result(), 4);
  EXPECT_NULL(request.native()->path);
  EXPECT_NULL(request.native()->ptr);
  state.file.close(value, _offset_closed);
}

static void _offset_written(UvFs request, Var value) {
  OffsetState *state = value.pointer();
  uv_thread_t current = uv_thread_self();
  state.callback_thread &= uv_thread_equal(&state.driver, &current);
  state.write_calls++;
  EXPECT_INT_EQ(request.operation(), UV_FS_WRITE);
  EXPECT_INT_EQ(request.result(), 3);
  EXPECT_NULL(request.native()->path);
  state.file.read(8, 1, value, _offset_read);
}

static void _offset_text_written(UvFs request, Var value) {
  OffsetState *state = value.pointer();
  state.write_calls++;
  EXPECT_INT_EQ(request.operation(), UV_FS_WRITE);
  EXPECT_INT_EQ(request.result(), 2);
  unsigned char source[] = { 'A', 0, 'B' };
  Bytes bytes = Bytes.new(1).append(source, sizeof(source));
  state.file.write_bytes(bytes, 2, value, _offset_written);
  memset(bytes, '!', bytes.len());
  bytes.free();
}

static void _offset_opened(UvFs request, Var value) {
  OffsetState *state = value.pointer();
  uv_thread_t current = uv_thread_self();
  state.callback_thread &= uv_thread_equal(&state.driver, &current);
  state.open_calls++;
  state.file = request.file();
  EXPECT_INT_EQ(request.operation(), UV_FS_OPEN);
  EXPECT_TRUE(state.file.native() >= 0);
  EXPECT_PTR_EQ(state.file.loop(), request.loop());
  EXPECT_NULL(request.native()->path);

  state.file.write(%"00", 0, value, _offset_text_written);
}

static void file_offset_io_copies_buffers_and_closes(void) {
  String path = _fs_path(%"offset");
  unlink(path);
  defer unlink(path);
  UvLoop loop = UvLoop.new();
  OffsetState state = {
    .driver = uv_thread_self(),
    .callback_thread = 1
  };
  Var value = Var.new(<p48>, &state);
  loop.open(
    path, UV_FS_O_RDWR | UV_FS_O_CREAT | UV_FS_O_TRUNC, 0600,
    value, _offset_opened
  );
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);

  EXPECT_INT_EQ(state.open_calls, 1);
  EXPECT_INT_EQ(state.write_calls, 2);
  EXPECT_INT_EQ(state.read_calls, 1);
  EXPECT_INT_EQ(state.close_calls, 1);
  EXPECT_TRUE(state.callback_thread);
  EXPECT_INT_EQ(state.read.len(), 4);
  unsigned char expected[] = { '0', 'A', 0, 'B' };
  EXPECT_TRUE(!memcmp(state.read, expected, sizeof(expected)));

  int caught = 0;
  try state.file.read(1, 0, void, _offset_read);
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"fs_read");
  }
  EXPECT_TRUE(caught);
  caught = 0;
  try state.file.write(%"x", 0, void, _offset_written);
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"fs_write");
  }
  EXPECT_TRUE(caught);
  caught = 0;
  try state.file.close(void, _offset_closed);
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"fs_close");
  }
  EXPECT_TRUE(caught);
  caught = 0;
  try state.file.native();
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"file_native");
  }
  EXPECT_TRUE(caught);
  EXPECT_NULL(loop.free());
}

typedef struct WholeState {
  UvFs request;
  Bytes bytes;
  size_t result;
  int calls;
} WholeState;

static void _whole_done(UvFs request, Var value) {
  WholeState *state = value.pointer();
  state.calls++;
  state.request = request;
  state.result = (size_t) request.result();
  if (request.operation() == UV_FS_READ) state.bytes = request;
  EXPECT_NULL(request.native()->path);
  EXPECT_NULL(request.native()->ptr);
}

static void whole_file_io_is_bounded_and_binary_safe(void) {
  String path = _fs_path(%"whole");
  unlink(path);
  defer unlink(path);
  UvLoop loop = UvLoop.new();
  defer loop.free();
  size_t length = 160 * 1024 + 3;
  unsigned char byte = 'x';
  Bytes payload = Bytes.new(1).append_fill(&byte, length);
  ((unsigned char *) payload)[65536] = 0;
  ((unsigned char *) payload)[length - 1] = 'z';
  WholeState written = { 0 };
  loop.write_file_bytes(
    path, payload, Var.new(<p48>, &written), _whole_done
  );
  memset(payload, '!', payload.len());
  payload.free();
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(written.calls, 1);
  EXPECT_INT_EQ(written.result, length);
  EXPECT_INT_EQ(written.request.operation(), UV_FS_WRITE);
  EXPECT_INT_EQ(written.request.native()->fs_type, UV_FS_WRITE);
  EXPECT_TRUE(written.request.native()->result > 0);
  EXPECT_TRUE(written.request.native()->result < (ssize_t) length);

  WholeState read = { 0 };
  loop.read_file(
    path, length, Var.new(<p48>, &read), _whole_done
  );
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(read.calls, 1);
  EXPECT_INT_EQ(read.result, length);
  EXPECT_INT_EQ(read.request.operation(), UV_FS_READ);
  EXPECT_INT_EQ(read.request.native()->fs_type, UV_FS_READ);
  EXPECT_INT_EQ(read.request.native()->result, 0);
  EXPECT_INT_EQ(read.bytes.len(), length);
  EXPECT_INT_EQ(((unsigned char *) read.bytes)[0], 'x');
  EXPECT_INT_EQ(((unsigned char *) read.bytes)[65536], 0);
  EXPECT_INT_EQ(((unsigned char *) read.bytes)[length - 1], 'z');

  WholeState limited = { 0 };
  UvFs limited_request = loop.read_file(
    path, length - 1, Var.new(<p48>, &limited), _whole_done
  );
  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(size-limit (library ?library) (operation ?operation)
         (limit ?limit) *): {
    caught = 1;
    EXPECT_STR_EQ(library.string(), %"libuv");
    EXPECT_STR_EQ(operation.string(), %"read_file");
    EXPECT_INT_EQ(limit.integer(), length - 1);
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(limited.calls, 0);
  EXPECT_INT_EQ(limited_request.result(), UV_ENOBUFS);
  errno = 0;
  EXPECT_INT_EQ(fcntl(limited_request.native()->file, F_GETFD), -1);
  EXPECT_INT_EQ(errno, EBADF);
  EXPECT_NULL(limited_request.native()->path);
  EXPECT_NULL(limited_request.native()->ptr);
  EXPECT_NULL(limited_request.native()->bufs);
  caught = 0;
  try limited_request.bytes();
  catch %(size-limit (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"read_file");
  }
  EXPECT_TRUE(caught);

  WholeState text_written = { 0 }, text_read = { 0 };
  loop.write_file(
    path, %"text", Var.new(<p48>, &text_written), _whole_done
  );
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(text_written.result, 4);
  loop.read_file(
    path, 4, Var.new(<p48>, &text_read), _whole_done
  );
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(text_read.bytes.len(), 4);
  EXPECT_TRUE(!memcmp(text_read.bytes, "text", 4));

  Bytes empty = Bytes.new(1);
  WholeState emptied = { 0 }, empty_read = { 0 };
  loop.write_file_bytes(
    path, empty, Var.new(<p48>, &emptied), _whole_done
  );
  empty.free();
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(emptied.result, 0);
  EXPECT_INT_EQ(emptied.request.native()->fs_type, UV_FS_WRITE);
  EXPECT_INT_EQ(emptied.request.native()->result, 0);
  loop.read_file(
    path, 0, Var.new(<p48>, &empty_read), _whole_done
  );
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_NOT_NULL((void *) empty_read.bytes);
  EXPECT_INT_EQ(empty_read.bytes.len(), 0);
}

typedef struct MetadataState {
  UvFs stat_request;
  UvFs scan_request;
  int stat_calls;
  int scan_calls;
} MetadataState;

static void _stat_done(UvFs request, Var value) {
  MetadataState *state = value.pointer();
  state.stat_request = request;
  state.stat_calls++;
}

static void _scan_done(UvFs request, Var value) {
  MetadataState *state = value.pointer();
  state.scan_request = request;
  state.scan_calls++;
}

static int _entry_index(UvFs scan, String name) {
  for (int index = 0; index < (int) scan.entry_count(); index++) {
    if (scan.entry_name(index).equal(name)) return index;
  }
  return -1;
}

static void stat_and_scan_results_are_independent_copies(void) {
  String directory = _fs_path(%"metadata");
  String file_path = %"$directory/file.bin";
  String subdirectory = %"$directory/subdir";
  String link_path = %"$directory/link";
  unlink(link_path);
  unlink(file_path);
  rmdir(subdirectory);
  rmdir(directory);
  mkdir(directory, 0700);
  mkdir(subdirectory, 0700);
  File file = File.open(file_path, %"w");
  file.puts(%"five\n");
  file.close();
  symlink("file.bin", link_path);
  defer {
    unlink(link_path);
    unlink(file_path);
    rmdir(subdirectory);
    rmdir(directory);
  }

  UvLoop loop = UvLoop.new();
  defer loop.free();
  MetadataState state = { 0 };
  Var value = Var.new(<p48>, &state);
  loop.stat(file_path, value, _stat_done);
  loop.scan(directory, value, _scan_done);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(state.stat_calls, 1);
  EXPECT_INT_EQ(state.scan_calls, 1);

  UvStat stat = state.stat_request.stat();
  EXPECT_INT_EQ(stat.size(), 5);
  EXPECT_TRUE(S_ISREG(stat.mode()));
  EXPECT_TRUE(stat.modified_seconds() > 0);
  EXPECT_TRUE(stat.modified_nanoseconds() >= 0);
  EXPECT_NOT_NULL(stat.native());
  EXPECT_TRUE(stat.native() != &state.stat_request.native()->statbuf);
  int file_index = _entry_index(state.scan_request, %"file.bin");
  int dir_index = _entry_index(state.scan_request, %"subdir");
  int link_index = _entry_index(state.scan_request, %"link");
  EXPECT_TRUE(file_index >= 0);
  EXPECT_TRUE(dir_index >= 0);
  EXPECT_TRUE(link_index >= 0);
  EXPECT_INT_EQ(
    state.scan_request.entry_type(file_index), UV_DIRENT_FILE
  );
  EXPECT_INT_EQ(
    state.scan_request.entry_type(dir_index), UV_DIRENT_DIR
  );
  EXPECT_INT_EQ(
    state.scan_request.entry_type(link_index), UV_DIRENT_LINK
  );

  state.stat_request.native()->statbuf.st_size = 999;
  unlink(link_path);
  unlink(file_path);
  rmdir(subdirectory);
  EXPECT_INT_EQ(stat.size(), 5);
  EXPECT_STR_EQ(
    state.scan_request.entry_name(file_index), %"file.bin"
  );
  int caught = 0;
  try state.scan_request.entry_name(-1);
  catch %(bad-arg (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"fs_entry_name");
  }
  EXPECT_TRUE(caught);
  caught = 0;
  try state.scan_request.entry_type(
    (int) state.scan_request.entry_count()
  );
  catch %(bad-arg (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"fs_entry_type");
  }
  EXPECT_TRUE(caught);
}

static void _count_fs(UvFs request, Var value) {
  int *calls = value.pointer();
  (*calls)++;
  (void) request;
}

typedef struct CloseErrorState {
  UvFile file;
  int close_calls;
} CloseErrorState;

static void _close_error_opened(UvFs request, Var value) {
  CloseErrorState *state = value.pointer();
  state.file = request.file();
}

static void _close_error_done(UvFs request, Var value) {
  CloseErrorState *state = value.pointer();
  state.close_calls++;
  (void) request;
}

static void whole_transfer_and_close_errors_release_descriptors(void) {
  String directory = _fs_path(%"read-directory");
  String path = _fs_path(%"raw-closed");
  rmdir(directory);
  unlink(path);
  mkdir(directory, 0700);
  File seed = File.open(path, %"w");
  seed.puts(%"data");
  seed.close();
  defer {
    rmdir(directory);
    unlink(path);
  }

  UvLoop loop = UvLoop.new();
  int calls = 0;
  Var count = Var.new(<p48>, &calls);
  UvFs read = loop.read_file(directory, 64, count, _count_fs);
  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(io-fail (library ?library) (operation ?operation)
         (status ?status) *): {
    caught = 1;
    EXPECT_STR_EQ(library.string(), %"libuv");
    EXPECT_STR_EQ(operation.string(), %"fs_read");
    EXPECT_INT_EQ(status.integer(), UV_EISDIR);
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(calls, 0);
  EXPECT_INT_EQ(read.result(), UV_EISDIR);
  EXPECT_INT_EQ(read.native()->fs_type, UV_FS_READ);
  EXPECT_INT_EQ(read.native()->result, UV_EISDIR);
  errno = 0;
  EXPECT_INT_EQ(fcntl(read.native()->file, F_GETFD), -1);
  EXPECT_INT_EQ(errno, EBADF);

  CloseErrorState opened = { 0 };
  Var value = Var.new(<p48>, &opened);
  loop.open(path, UV_FS_O_RDONLY, 0, value, _close_error_opened);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  int descriptor = opened.file.native();
  EXPECT_INT_EQ(close(descriptor), 0);
  UvFs closing = opened.file.close(value, _close_error_done);
  caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(io-fail (library *) (operation ?operation)
         (status ?status) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"fs_close");
    EXPECT_INT_EQ(status.integer(), UV_EBADF);
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(closing.result(), UV_EBADF);
  EXPECT_INT_EQ(opened.close_calls, 0);
  EXPECT_NULL(loop.free());
}

static void _expect_missing(UvLoop loop, UvFs request, String operation) {
  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(io-fail (library ?library) (operation ?actual)
         (status ?status) (name ?name) (message ?message) *): {
    caught = 1;
    EXPECT_STR_EQ(library.string(), %"libuv");
    EXPECT_STR_EQ(actual.string(), operation);
    EXPECT_INT_EQ(status.integer(), UV_ENOENT);
    EXPECT_STR_EQ(name.string(), %"ENOENT");
    EXPECT_STR_EQ(message.string(), String.new(uv_strerror(UV_ENOENT)));
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(request.result(), UV_ENOENT);
}

static void missing_paths_preserve_libuv_errors(void) {
  String path = _fs_path(%"absent");
  unlink(path);
  UvLoop loop = UvLoop.new();
  defer loop.free();
  int calls = 0;
  Var value = Var.new(<p48>, &calls);
  UvFs read = loop.read_file(path, 32, value, _count_fs);
  _expect_missing(loop, read, %"fs_open");
  UvFs stat = loop.stat(path, value, _count_fs);
  _expect_missing(loop, stat, %"fs_stat");
  UvFs scan = loop.scan(path, value, _count_fs);
  _expect_missing(loop, scan, %"fs_scandir");
  EXPECT_INT_EQ(calls, 0);
}

typedef struct PoolBlocker {
  uv_work_t work;
  uv_sem_t started;
  uv_sem_t release;
} PoolBlocker;

static void _hold_fs_worker(uv_work_t *request) {
  PoolBlocker *blocker = request->data;
  uv_sem_post(&blocker->started);
  uv_sem_wait(&blocker->release);
}

static void _fs_worker_released(uv_work_t *request, int status) {
  (void) request;
  (void) status;
}

typedef struct CancelState {
  UvFs native_owner;
  int calls;
  int cancelled;
  int cleaned;
} CancelState;

static void _cancel_done(UvFs request, Var value) {
  CancelState *state = value.pointer();
  state.calls++;
  state.cancelled = request.cancelled();
  state.cleaned = request.native()->path == NULL;
  state.native_owner = request;
}

static void cancelled_fs_request_completes_once(void) {
  UvLoop loop = UvLoop.new();
  PoolBlocker blocker = { 0 };
  CancelState state = { 0 };
  EXPECT_INT_EQ(uv_sem_init(&blocker.started, 0), 0);
  EXPECT_INT_EQ(uv_sem_init(&blocker.release, 0), 0);
  blocker.work.data = &blocker;
  EXPECT_INT_EQ(uv_queue_work(
    loop.native(), &blocker.work, _hold_fs_worker, _fs_worker_released
  ), 0);
  uv_sem_wait(&blocker.started);
  UvFs request = loop.stat(
    %"/tmp", Var.new(<p48>, &state), _cancel_done
  );
  uv_fs_t *native = request.native();
  EXPECT_TRUE(request.cancel());

  int caught = 0;
  try loop.free();
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"loop_free");
  }
  EXPECT_TRUE(caught);
  uv_sem_post(&blocker.release);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(state.calls, 1);
  EXPECT_TRUE(state.cancelled);
  EXPECT_TRUE(state.cleaned);
  EXPECT_INT_EQ(request.result(), UV_ECANCELED);
  EXPECT_PTR_EQ(request.native(), native);
  EXPECT_FALSE(request.cancel());
  uv_sem_destroy(&blocker.started);
  uv_sem_destroy(&blocker.release);
  EXPECT_NULL(loop.free());
}

typedef struct PendingState {
  UvFile file;
  int read_calls;
  int close_calls;
} PendingState;

static void _pending_closed(UvFs request, Var value) {
  PendingState *state = value.pointer();
  state.close_calls++;
  (void) request;
}

static void _pending_read(UvFs request, Var value) {
  PendingState *state = value.pointer();
  state.read_calls++;
  (void) request;
}

static void _pending_open(UvFs request, Var value) {
  PendingState *state = value.pointer();
  state.file = request.file();
}

static void file_close_and_loop_free_reject_live_work(void) {
  String path = _fs_path(%"pending");
  unlink(path);
  defer unlink(path);
  File seed = File.open(path, %"w");
  seed.puts(%"pending");
  seed.close();
  UvLoop loop = UvLoop.new();
  PendingState state = { 0 };
  Var value = Var.new(<p48>, &state);
  loop.open(path, UV_FS_O_RDONLY, 0, value, _pending_open);
  loop.run(UV_RUN_DEFAULT);

  int caught = 0;
  try loop.free();
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"loop_free");
  }
  EXPECT_TRUE(caught);

  PoolBlocker blocker = { 0 };
  uv_sem_init(&blocker.started, 0);
  uv_sem_init(&blocker.release, 0);
  blocker.work.data = &blocker;
  EXPECT_INT_EQ(uv_queue_work(
    loop.native(), &blocker.work, _hold_fs_worker, _fs_worker_released
  ), 0);
  uv_sem_wait(&blocker.started);
  state.file.read(7, 0, value, _pending_read);
  caught = 0;
  try state.file.close(value, _pending_closed);
  catch %(bad-state (library *) (operation ?operation) *): {
    caught = 1;
    EXPECT_STR_EQ(operation.string(), %"fs_close");
  }
  EXPECT_TRUE(caught);
  uv_sem_post(&blocker.release);
  loop.run(UV_RUN_DEFAULT);
  EXPECT_INT_EQ(state.read_calls, 1);
  state.file.close(value, _pending_closed);
  loop.run(UV_RUN_DEFAULT);
  EXPECT_INT_EQ(state.close_calls, 1);
  uv_sem_destroy(&blocker.started);
  uv_sem_destroy(&blocker.release);
  EXPECT_NULL(loop.free());
}

typedef struct FailureState {
  UvStat copied;
  int calls;
} FailureState;

static void _failing_stat(UvFs request, Var value) {
  FailureState *state = value.pointer();
  state.calls++;
  state.copied = request.stat();
  EXPECT_NULL(request.native()->path);
  raise %(malformed (library "test")
          (reason "a filesystem callback failed"));
}

static void filesystem_callback_error_returns_and_loop_resumes(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  FailureState failed = { 0 };
  loop.stat(%"/tmp", Var.new(<p48>, &failed), _failing_stat);
  int caught = 0;
  try loop.run(UV_RUN_DEFAULT);
  catch %(malformed (library ?library) (reason ?reason) *): {
    caught = 1;
    EXPECT_STR_EQ(library.string(), %"test");
    EXPECT_STR_EQ(reason.string(), %"a filesystem callback failed");
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(failed.calls, 1);
  EXPECT_TRUE(S_ISDIR(failed.copied.mode()));

  MetadataState resumed = { 0 };
  loop.stat(%"/tmp", Var.new(<p48>, &resumed), _stat_done);
  EXPECT_INT_EQ(loop.run(UV_RUN_DEFAULT), 0);
  EXPECT_INT_EQ(resumed.stat_calls, 1);
  EXPECT_TRUE(S_ISDIR(resumed.stat_request.stat().mode()));
}

void fs_suite(void) {
  $test.run(file_offset_io_copies_buffers_and_closes);
  $test.run(whole_file_io_is_bounded_and_binary_safe);
  $test.run(stat_and_scan_results_are_independent_copies);
  $test.run(whole_transfer_and_close_errors_release_descriptors);
  $test.run(missing_paths_preserve_libuv_errors);
  $test.run(cancelled_fs_request_completes_once);
  $test.run(file_close_and_loop_free_reject_live_work);
  $test.run(filesystem_callback_error_returns_and_loop_resumes);
}

int main(void) {
  setenv("UV_THREADPOOL_SIZE", "1", 1);
  TestHarness_begin();
  $test.suite(fs_suite);
  return TestHarness_finish();
}
