/* Fixed-body C comparison for the notes loopback benchmark. */
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int listener;
static const char body[] = "{\"id\":\"1\",\"title\":\"benchmark\",\"body\":\"hello\",\"tags\":[],\"created\":0,\"updated\":0}";

static int write_all(int fd, const char *data, size_t size) {
  while (size) {
    ssize_t n = send(fd, data, size, 0);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) return 0;
    data += n;
    size -= (size_t)n;
  }
  return 1;
}

static void *worker(void *unused) {
  (void)unused;
  char response[512];
  int length = snprintf(response, sizeof response,
    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
    "Content-Length: %zu\r\nConnection: keep-alive\r\n\r\n%s",
    strlen(body), body);
  for (;;) {
    int fd = accept(listener, NULL, NULL);
    if (fd < 0) { if (errno == EINTR) continue; return NULL; }
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    struct timeval timeout = {5, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    char request[8192];
    size_t used = 0;
    for (;;) {
      ssize_t n = recv(fd, request + used, sizeof request - used - 1, 0);
      if (n < 0 && errno == EINTR) continue;
      if (n <= 0) break;
      used += (size_t)n;
      request[used] = 0;
      char *end;
      while ((end = strstr(request, "\r\n\r\n"))) {
        if (strncmp(request, "GET /api/notes/1 HTTP/1.1\r\n", 27)) goto finished;
        if (!write_all(fd, response, (size_t)length)) goto finished;
        size_t consumed = (size_t)(end - request) + 4;
        memmove(request, request + consumed, used - consumed);
        used -= consumed;
        request[used] = 0;
      }
      if (used == sizeof request - 1) break;
    }
finished:
    close(fd);
  }
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int port = atoi(argv[1]), workers = atoi(argv[2]);
  if (port < 1 || port > 65535 || workers < 1 || workers > 1024) return 2;
  signal(SIGPIPE, SIG_IGN);
  listener = socket(AF_INET, SOCK_STREAM, 0);
  if (listener < 0) return 1;
  int one = 1;
  setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  struct sockaddr_in address = {0};
  address.sin_family = AF_INET;
  address.sin_port = htons((unsigned short)port);
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (bind(listener, (struct sockaddr *)&address, sizeof address) ||
      listen(listener, 128)) return 1;
  pthread_t *threads = calloc((size_t)workers, sizeof *threads);
  if (!threads) return 1;
  for (int i = 0; i < workers; ++i)
    if (pthread_create(&threads[i], NULL, worker, NULL)) return 1;
  for (int i = 0; i < workers; ++i) pthread_join(threads[i], NULL);
  free(threads);
  close(listener);
  return 0;
}
