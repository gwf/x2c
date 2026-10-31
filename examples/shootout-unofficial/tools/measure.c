/*
 * measure.c -- fresh-process elapsed time and resource measurement
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static uint64_t timespec_ns(struct timespec value) {
  return (uint64_t) value.tv_sec * UINT64_C(1000000000) +
         (uint64_t) value.tv_nsec;
}

static uint64_t timeval_ns(struct timeval value) {
  return (uint64_t) value.tv_sec * UINT64_C(1000000000) +
         (uint64_t) value.tv_usec * UINT64_C(1000);
}

static int monotonic_now(struct timespec *value) {
#ifdef CLOCK_MONOTONIC_RAW
  return clock_gettime(CLOCK_MONOTONIC_RAW, value);
#else
  return clock_gettime(CLOCK_MONOTONIC, value);
#endif
}

int main(int argc, char **argv) {
  struct timespec start, finish;
  struct rusage usage;
  int status;

  if (argc < 2) {
    fprintf(stderr, "usage: measure PROGRAM [ARG ...]\n");
    return 2;
  }
  if (monotonic_now(&start) != 0) {
    perror("clock_gettime");
    return 2;
  }

  pid_t child = fork();
  if (child < 0) {
    perror("fork");
    return 2;
  }
  if (child == 0) {
    int devnull = open("/dev/null", O_WRONLY);
    if (devnull < 0 || dup2(devnull, STDOUT_FILENO) < 0) _exit(126);
    if (devnull != STDOUT_FILENO) close(devnull);
    execv(argv[1], &argv[1]);
    _exit(errno == ENOENT ? 127 : 126);
  }

  while (wait4(child, &status, 0, &usage) < 0) {
    if (errno == EINTR) continue;
    perror("wait4");
    return 2;
  }
  if (monotonic_now(&finish) != 0) {
    perror("clock_gettime");
    return 2;
  }

  uint64_t elapsed = timespec_ns(finish) - timespec_ns(start);
  uint64_t user = timeval_ns(usage.ru_utime);
  uint64_t system = timeval_ns(usage.ru_stime);
#ifdef __APPLE__
  uint64_t max_rss = (uint64_t) usage.ru_maxrss;
#else
  uint64_t max_rss = (uint64_t) usage.ru_maxrss * UINT64_C(1024);
#endif
  int exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
  int signal = WIFSIGNALED(status) ? WTERMSIG(status) : 0;

  printf(
    "{\"elapsed_ns\":%" PRIu64 ",\"user_ns\":%" PRIu64
    ",\"system_ns\":%" PRIu64 ",\"max_rss_bytes\":%" PRIu64
    ",\"exit_code\":%d,\"signal\":%d}\n",
    elapsed, user, system, max_rss, exit_code, signal
  );
  return exit_code == 0 && signal == 0 ? 0 : 1;
}
