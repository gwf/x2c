/* inprocess-notes.x -- optional Thread.run / Task.run Notes service probe

   SQLite, row conversion, and JSON are real Notes work. HTTP parsing and
   sockets are excluded. The batch owns all borrowed request storage until
   the database queue drains and its native thread joins, including failure.
*/
#include "notes-database.x"
#include "task.x"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>
#include <sqlite3.h>

typedef struct Batch Batch;
typedef struct Client {
  Batch *batch;
  NotesRequest job;
  int index;
  size_t count, capacity, bytes;
  double *latencies;
} Client;

struct Batch {
  Notes app;
  Client *clients;
  Logger logger;
  Pool parent;
  Scope owner;
  int count, record, fail;
  double stop_at;
  char *expected;
  size_t expected_size;
};

int main(int argc, char **argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: inprocess-notes MODE STORE [CLIENTS WARMUP SECONDS]\n"
      "MODE: prepare, thread, task, thread-fail, task-fail\n");
    return 2;
  }
  try {
    auto { return run(argc, argv); }
  }
  catch %(?cause *detail): {
    Stderr.printf("inprocess-notes: %s %s\n", cause, detail);
    return 1;
  }
}

static int run(int argc, char **argv) {
  const char *mode = argv[1];
  int prepare = !strcmp(mode, "prepare"), task = !strncmp(mode, "task", 4);
  int fail = !strcmp(mode, "thread-fail") || !strcmp(mode, "task-fail");
  if (!prepare && strcmp(mode, "thread") && strcmp(mode, "task") && !fail)
    raise %(bad-arg (operation "benchmark mode"));
  int count = argc > 3 ? atoi(argv[3]) : 1;
  double warmup = argc > 4 ? atof(argv[4]) : 1;
  double duration = argc > 5 ? atof(argv[5]) : 5;
  if (count < 1 || count > 1024 || warmup < 0 || duration <= 0)
    raise %(bad-arg (operation "benchmark dimensions"));
  struct Batch batch = {.app = Notes.new(), .parent = Pool.current(),
    .owner = *Scope.top(), .count = count, .fail = fail};
  batch.clients = xcalloc(count, sizeof(Client));
  defer close_batch(&batch);
  batch.app.path = argv[2];
  batch.app.requests = Channel.new(<p48>, count);
  batch.app.database = Thread.start(
    Notes.database_worker, Var.new(<p48>, batch.app));
  batch.logger = Logger.new(<info>);
  batch.logger.add_stderr_sink();
  for (int i = 0; i < count; i++) {
    Client *client = &batch.clients[i];
    client.batch = &batch;
    client.index = i;
    client.job.reply = Channel.new(<symbol>, 1);
  }
  Client *first = &batch.clients[0];
  call(first, <open>, NULL);
  clear_request(first);
  if (prepare) {
    populate(first);
    puts("prepared,1000");
    return 0;
  }
  call(first, <get>, %("1"));
  String expected = render(first);
  batch.expected_size = expected.len();
  batch.expected = Scope.memdup_in(&batch.owner, expected, expected.len() + 1);
  clear_request(first);
  Array jobs = [];
  for (int i = 0; i < count; i++) {
    batch.clients[i].job.arguments = %("1");
    Var client = Var.new(<p48>, &batch.clients[i]);
    jobs.push(%!(void) => { client_loop(client.pointer()); return void; });
  }
  if (fail) return failure_run(&batch, jobs, task);
  if (warmup) {
    batch.stop_at = seconds(CLOCK_MONOTONIC) + warmup;
    launch(jobs, task);
  }
  batch.record = 1;
  double wall = seconds(CLOCK_MONOTONIC), cpu = seconds(CLOCK_PROCESS_CPUTIME_ID);
  batch.stop_at = wall + duration;
  launch(jobs, task);
  cpu = seconds(CLOCK_PROCESS_CPUTIME_ID) - cpu;
  wall = seconds(CLOCK_MONOTONIC) - wall;
  report(&batch, mode, wall, cpu);
  return 0;
}

static void close_batch(Batch *batch) {
  try {
    if (batch.app.database) {
      batch.app.requests.close();
      batch.app.database.join();
    }
  }
  finally {
    if (batch.app.database) batch.app.database.free();
    for (int i = 0; i < batch.count; i++) {
      Client *client = &batch.clients[i];
      clear_request(client);
      if (client.job.reply) client.job.reply.free();
      free(client.latencies);
    }
    if (batch.app.requests) batch.app.requests.free();
    if (batch.logger) batch.logger.free();
  }
}

static void clear_request(Client *client) {
  Scope.destroy(client.job.output);
  client.job.output = NULL;
  Pool.release(client.job.pool);
  client.job.pool = NULL;
  client.job.result = void;
  client.job.detail = NULL;
}

static void call(Client *client, Symbol operation, List arguments) {
  NotesRequest *job = &client.job;
  job.output = Scope.new();
  job.pool = client.batch.parent.retain_named("Notes request");
  job.operation = operation;
  job.arguments = arguments;
  job.cause = 0;
  job.result = void;
  client.batch.app.requests.send(Var.new(<p48>, job));
  if (job.reply.receive() is void)
    raise %(invariant (operation "Notes reply closed"));
  if (job.cause) Error.raise(job.cause, job.detail);
}

static String render(Client *client) {
  Scope.push(&client.job.output);
  defer Scope.pop();
  Pool previous = x2c_pool_exchange(client.job.pool);
  defer x2c_pool_exchange(previous);
  List row = client.job.result;
  if (!row) raise %(invariant (operation "Notes fixture row missing"));
  Var note = Notes.note_json(row);
  return note.json();
}

static void client_loop(Client *client) {
  Batch *batch = client.batch;
  Symbol operation = batch.fail && !client.index ? <invalid> : <get>;
  while (seconds(CLOCK_MONOTONIC) < batch.stop_at) {
    double start = seconds(CLOCK_MONOTONIC);
    call(client, operation, client.job.arguments);
    String encoded = render(client);
    if (encoded.len() != batch.expected_size ||
        memcmp(encoded, batch.expected, batch.expected_size))
      raise %(invariant (operation "Notes response differs"));
    batch.logger.info(<http>, %(status 200), %(path "/api/notes/1"));
    size_t bytes = encoded.len();
    clear_request(client);
    double elapsed = seconds(CLOCK_MONOTONIC) - start;
    if (batch.record) {
      record(client, elapsed);
      client.bytes += bytes;
    }
  }
}

static void launch(Array jobs, int task) {
  if (task) Task.run(jobs, NULL);
  else Thread.run(jobs, NULL);
}

static int failure_run(Batch *batch, Array jobs, int task) {
  int caught = 0;
  batch.stop_at = seconds(CLOCK_MONOTONIC) + 1;
  try launch(jobs, task);
  catch %(join-fail (errors ?errors)): {
    foreach (List error in errors.list())
      if (error.assoc(<code>) == <bad-arg>) caught = 1;
  }
  printf("{\"expected_failure\":%s}\n", caught ? "true" : "false");
  return !caught;
}

static void populate(Client *client) {
  for (int i = 1; i <= 1000; i++) {
    String title = String.printf("Note %04d", i);
    call(client, <create>, $(title, "hello", "[\"work\"]", 1700000000, 1700000000));
    clear_request(client);
  }
}

static double seconds(clockid_t clock) {
  struct timespec now;
  clock_gettime(clock, &now);
  return now.tv_sec + now.tv_nsec / 1e9;
}

static void record(Client *client, double elapsed) {
  if (client.count == client.capacity) {
    size_t capacity = client.capacity ? client.capacity * 2 : 4096;
    double *values = realloc(client.latencies, capacity * sizeof(double));
    if (!values) raise %(alloc-fail);
    client.latencies = values;
    client.capacity = capacity;
  }
  client.latencies[client.count++] = elapsed;
}

static int compare_latency(const void *a, const void *b) {
  double x = *(const double *)a, y = *(const double *)b;
  return (x > y) - (x < y);
}

static void report(Batch *batch, const char *mode, double wall, double cpu) {
  size_t count = 0, bytes = 0;
  for (int i = 0; i < batch.count; i++) {
    count += batch.clients[i].count;
    bytes += batch.clients[i].bytes;
  }
  if (!count) raise %(invariant (operation "Notes sample completed no requests"));
  double *all = xmalloc(count * sizeof(double));
  size_t at = 0;
  for (int i = 0; i < batch.count; i++) {
    Client *client = &batch.clients[i];
    memcpy(all + at, client.latencies, client.count * sizeof(double));
    at += client.count;
  }
  qsort(all, count, sizeof(double), compare_latency);
  struct rusage usage;
  getrusage(RUSAGE_SELF, &usage);
  printf("{\"mode\":\"%s\",\"clients\":%d,\"requests\":%zu,\"bytes\":%zu,"
    "\"wall_s\":%.9f,\"cpu_s\":%.9f,\"requests_per_s\":%.3f,"
    "\"cpu_us_per_request\":%.3f,\"p50_us\":%.3f,\"p99_us\":%.3f,"
    "\"peak_rss_bytes\":%ld,\"sqlite_version\":\"%s\"}\n", mode, batch.count, count, bytes, wall, cpu,
    count / wall, cpu * 1e6 / count, all[count / 2] * 1e6,
    all[(count - 1) * 99 / 100] * 1e6, usage.ru_maxrss, sqlite3_libversion());
}
