/*  load.x -- keep-alive loopback load for the notes benchmark

    Copyright (c) 2026 Gary William Flake.
*/
#include "net.x"
#include <time.h>
#include <strings.h>
#include <stdlib.h>

struct Samples {
  double *values;
  size_t count, capacity;
};

struct Load {
  int port;
  double deadline;
  struct Samples *samples;
  const char *request;
  int index, update;
};

static double now(void) {
  struct timespec value;
  clock_gettime(CLOCK_MONOTONIC, &value);
  return value.tv_sec + value.tv_nsec / 1e9;
}

static void record(struct Samples *samples, double elapsed) {
  if (samples.count == samples.capacity) {
    size_t capacity = samples.capacity ? samples.capacity * 2 : 1024;
    void *values = realloc(samples.values, capacity * sizeof(double));
    if (!values) raise %(alloc-fail);
    samples.values = values;
    samples.capacity = capacity;
  }
  samples.values[samples.count++] = elapsed;
}

static void response_line(Socket socket, char *line, int size) {
  if (!socket.input.gets(line, size))
    raise %(io-fail (operation "benchmark response line"));
  size_t length = strlen(line);
  if (length < 2 || strcmp(line + length - 2, "\r\n"))
    raise %(malformed (operation "benchmark response line"));
}

static void response(Socket socket) {
  char line[8192];
  response_line(socket, line, sizeof(line));
  if (strncmp(line, "HTTP/1.1 200 ", 13))
    raise %(io-fail (operation "benchmark response status"));
  long length = -1;
  for (;;) {
    response_line(socket, line, sizeof(line));
    if (!strcmp(line, "\r\n")) break;
    if (!strncasecmp(line, "Content-Length:", 15)) {
      if (length >= 0)
        raise %(malformed (operation "duplicate benchmark response length"));
      char *end;
      length = strtol(line + 15, &end, 10);
      if (end == line + 15 || strcmp(end, "\r\n"))
        raise %(malformed (operation "benchmark response length"));
    }
  }
  if (length < 0 || length > 1048576)
    raise %(malformed (operation "benchmark response length"));
  char body[4096];
  while (length) {
    size_t size = length < sizeof(body) ? (size_t)length : sizeof(body);
    if (socket.input.read(body, 1, size) != size)
      raise %(io-fail (operation "benchmark response body"));
    length -= size;
  }
}

static Var load(const void *data, size_t ignored) {
  (void) ignored;
  const struct Load *input = data;
  Socket socket = auto Socket.connect("127.0.0.1", input.port, 5000);
  socket.set_timeout(5000);
  char updated[512];
  unsigned long long sequence = 0;
  while (now() < input.deadline) {
    const char *request = input.request;
    /* Fixed-width formatting precedes the round-trip timer. Its cost still
       belongs to the elapsed throughput interval. */
    if (input.update) {
      snprintf(updated, sizeof(updated), request, input.index, sequence++);
      request = updated;
    }
    double start = now();
    socket.output.puts(request);
    if (socket.output.flush()) {
      int error = errno;
      raise %(io-fail (operation "benchmark request flush") (errno $error));
    }
    response(socket);
    /* Recording runs between requests, outside the measured round trip. */
    record(input.samples, (now() - start) * 1e6);
  }
  return void;
}

static int compare(const void *a, const void *b) {
  double left = *(const double *)a, right = *(const double *)b;
  return (left > right) - (left < right);
}

int main(int argc, char **argv) {
  if (argc != 4 && argc != 5) {
    fprintf(stderr, "usage: load PORT CONNECTIONS SECONDS [lookup|update]\n");
    return 2;
  }
  const char *request = "GET /api/notes/1 HTTP/1.1\r\n"
    "Host: localhost\r\nConnection: keep-alive\r\n\r\n";
  int update = argc == 5 && !strcmp(argv[4], "update");
  if (update)
    request = "PUT /api/notes/1 HTTP/1.1\r\nHost: localhost\r\n"
      "Connection: keep-alive\r\nContent-Type: application/json\r\n"
      "Content-Length: 78\r\n\r\n"
      "{\"title\":\"benchmark-%04d-%020llu\",\"body\":\"hello\","
      "\"tags\":[\"work\"]}";
  else if (argc == 5 && strcmp(argv[4], "lookup")) return 2;
  int port = atoi(argv[1]), connections = atoi(argv[2]);
  double seconds = atof(argv[3]);
  if (port < 1 || port > 65535 || connections < 1 ||
      connections > 1024 || seconds <= 0) return 2;
  struct Samples *samples = calloc(connections, sizeof(struct Samples));
  if (!samples) raise %(alloc-fail);
  defer {
    for (int i = 0; i < connections; ++i) free(samples[i].values);
    free(samples);
  }
  Array pending = [];
  double start = now();
  pending.reserve(connections);
  try {
    for (int i = 0; i < connections; ++i) {
      struct Load input = {
        port, start + seconds, &samples[i], request, i, update};
      pending.push(Thread.start_raw(load, &input, sizeof(input)));
    }
  }
  finally Thread.finish_all(pending);
  double elapsed = now() - start;
  size_t count = 0;
  for (int i = 0; i < connections; ++i) count += samples[i].count;
  double *values = malloc((count ? count : 1) * sizeof(double));
  if (!values) raise %(alloc-fail);
  defer free(values);
  size_t offset = 0;
  for (int i = 0; i < connections; ++i) {
    if (samples[i].count)
      memcpy(values + offset, samples[i].values,
        samples[i].count * sizeof(double));
    offset += samples[i].count;
  }
  if (!count) return 1;
  qsort(values, count, sizeof(double), compare);
  printf("{\"requests\":%zu,\"elapsed_s\":%.6f,\"requests_per_s\":%.3f,"
    "\"p50_us\":%.3f,\"p99_us\":%.3f}\n", count, elapsed, count / elapsed,
    values[(count - 1) / 2], values[(count - 1) * 99 / 100]);
  return 0;
}
