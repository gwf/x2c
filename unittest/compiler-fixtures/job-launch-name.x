#include "process.x"
#include <stddef.h>

typedef struct Launch { int value; } Launch;
typedef struct ExpectedLaunch {
  String dir, input, stdout_path, stderr_path;
  int has_input, capture_output, capture_errors, errors_to_output;
  char **environment;
} ExpectedLaunch;
typedef struct ExpectedJob {
  List stages;
  ExpectedLaunch launch;
  long *pids;
  int *statuses;
  int count, started, finished, status, nul_output, nul_errors;
  File output_file, errors_file;
  String output_text, errors_text;
} ExpectedJob;

_Static_assert(sizeof(JobLaunch) == sizeof(ExpectedLaunch), "launch size");
_Static_assert(_Alignof(JobLaunch) == _Alignof(ExpectedLaunch), "alignment");
_Static_assert(sizeof(struct Job) == sizeof(ExpectedJob), "Job size");
_Static_assert(offsetof(struct Job, stages) ==
  offsetof(ExpectedJob, stages), "Job field offset");
_Static_assert(offsetof(struct Job, launch) ==
  offsetof(ExpectedJob, launch), "Job field offset");
_Static_assert(offsetof(struct Job, pids) ==
  offsetof(ExpectedJob, pids), "Job field offset");
_Static_assert(offsetof(struct Job, statuses) ==
  offsetof(ExpectedJob, statuses), "Job field offset");
_Static_assert(offsetof(struct Job, count) ==
  offsetof(ExpectedJob, count), "Job field offset");
_Static_assert(offsetof(struct Job, started) ==
  offsetof(ExpectedJob, started), "Job field offset");
_Static_assert(offsetof(struct Job, finished) ==
  offsetof(ExpectedJob, finished), "Job field offset");
_Static_assert(offsetof(struct Job, status) ==
  offsetof(ExpectedJob, status), "Job field offset");
_Static_assert(offsetof(struct Job, nul_output) ==
  offsetof(ExpectedJob, nul_output), "Job field offset");
_Static_assert(offsetof(struct Job, nul_errors) ==
  offsetof(ExpectedJob, nul_errors), "Job field offset");
_Static_assert(offsetof(struct Job, output_file) ==
  offsetof(ExpectedJob, output_file), "Job field offset");
_Static_assert(offsetof(struct Job, errors_file) ==
  offsetof(ExpectedJob, errors_file), "Job field offset");
_Static_assert(offsetof(struct Job, output_text) ==
  offsetof(ExpectedJob, output_text), "Job field offset");
_Static_assert(offsetof(struct Job, errors_text) ==
  offsetof(ExpectedJob, errors_text), "Job field offset");

int main(void) {
  Launch user = {3};
  Job job = %(printf token).job();
  printf("%d %s %d\n", user.value, (const char *)job.output(), job.status());
  return 0;
}
