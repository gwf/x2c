/*  net.x -- blocking TCP sockets backed by File streams

    Copyright (c) 2026 Gary William Flake

    Each socket owns separate input and output streams because stdio update
    streams require positioning between reading and writing. Listener.stop
    and Thread.stop are observed within one 50 ms poll interval. Close the
    listener only after its accepting thread has finished.
*/

#pragma once
#include "x2c.x"
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

/** An owned TCP listener. `stop` may be called from another thread;
    `accept` and `close` each have one owner. */
class Listener struct { int fd; String host; int port, stopped; } *;

/** An owned TCP connection. Use ordinary File operations on `input` and
    `output`, and flush output at message boundaries. The socket's Scope or
    `close` releases both streams. */
class Socket struct { int fd; File input, output; String peer; } *;

protocol Cleanup(Listener);
protocol Cleanup(Socket);
/** Releases the listener when a managed local leaves its block. */
void Listener.cleanup(Listener listener) { listener.close(); }
/** Releases both streams when a managed local leaves its block. */
void Socket.cleanup(Socket socket) { socket.close(); }

static pthread_once_t sigpipe_once = (pthread_once_t) PTHREAD_ONCE_INIT;

// listeners

/** Binds a TCP listener. Port zero selects an available port; a null host
    binds passive addresses. IPv6 listeners request dual-stack operation.
    The first bind or connect ignores SIGPIPE process-wide.
    Raises: `<bad-arg>` for an invalid port, `<not-found>` on resolution
    failure, or `<io-fail>` with operation and errno on a host failure. */
Listener Listener.bind(String host, int port) {
  _port(port, "Listener.bind");
  _ignore_sigpipe();
  struct addrinfo *addresses = _resolve(host, port, AI_PASSIVE);
  defer freeaddrinfo(addresses);
  int fd = -1, error = EADDRNOTAVAIL;
  for (struct addrinfo *at = addresses; at; at = at->ai_next) {
    fd = _bind(at);
    if (fd >= 0) break;
    error = errno;
  }
  if (fd < 0) _io("Listener.bind", error);
  defer if (fd >= 0) close(fd);
  int bound_port = _bound_port(fd);
  Listener listener = Scope.malloc_finalized(
    sizeof(struct Listener), _drop_listener);
  *listener = (struct Listener) {
    .fd = fd, .host = host, .port = bound_port, .stopped = 0
  };
  fd = -1;
  return listener;
}

/** Accepts a connection, or returns NULL after Listener.stop. Thread.stop
    transfers its cooperative cancellation cause, like a Channel wait.
    Raises: `<io-fail>` on a native accept or poll failure. */
Socket Listener.accept(Listener listener) {
  int fd = x2c_net_accept_fd(listener);
  return fd < 0 ? NULL : Socket.adopt(fd);
}

/** Internal descriptor handoff for the HTTP acceptor. Returns an owned fd,
    or -1 after Listener.stop, with the same failure behavior as accept. */
int x2c_net_accept_fd(Listener listener) {
  struct pollfd wait = { .fd = listener.fd, .events = POLLIN };
  while (!_stopped(listener)) {
    int ready = poll(&wait, 1, 50);
    if (ready < 0 && errno == EINTR) continue;
    if (ready < 0) _io("Listener.accept", errno);
    if (!ready || _stopped(listener)) continue;
    int fd = accept(listener.fd, NULL, NULL);
    if (fd < 0 && (errno == EINTR || errno == EAGAIN)) continue;
    if (fd < 0) _io("Listener.accept", errno);
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)) {
      int error = errno;
      close(fd);
      _io("Listener.accept", error);
    }
    return fd;
  }
  return -1;
}

/** Returns the actual bound port, including when bind requested port zero. */
int Listener.port(Listener listener) => listener.port;

/** Writes the listener's fields, reading its stop state atomically. */
Buffer Listener.write_repr(Listener listener, Buffer out) {
  if (!listener) return listener.write_str(out);
  out.printf("Listener { fd: %d, host: ", listener.fd);
  listener.host.write_repr(out);
  int stopped = __atomic_load_n(&listener.stopped, __ATOMIC_ACQUIRE);
  return out.printf(", port: %d, stopped: %d }", listener.port, stopped);
}

/** Requests stopping from any thread. A blocked accept returns within one
    poll interval. The listener descriptor remains owned until close. */
void Listener.stop(Listener listener) {
  __atomic_store_n(&listener.stopped, 1, __ATOMIC_RELEASE);
}

/** Releases the listener. Call after its accepting thread has finished.
    Repeated calls are harmless. */
void Listener.close(Listener listener) {
  if (listener) _drop_listener(listener);
}

// connections

/** Connects to host, trying resolved addresses in order. A positive timeout
    bounds each connection attempt in milliseconds; zero waits indefinitely.
    The returned connection uses blocking File operations. The first bind or
    connect ignores SIGPIPE process-wide.
    Raises: `<bad-arg>` for a null host, invalid port, or negative timeout,
    `<not-found>` on resolution failure, or `<io-fail>` with errno. */
Socket Socket.connect(String host, int port, int timeout_ms) {
  _port(port, "Socket.connect");
  if (!host || timeout_ms < 0)
    raise %(bad-arg (operation "Socket.connect"));
  _ignore_sigpipe();
  struct addrinfo *addresses = _resolve(host, port, 0);
  defer freeaddrinfo(addresses);
  int error = ECONNREFUSED;
  for (struct addrinfo *at = addresses; at; at = at->ai_next) {
    int fd = _connect(at, timeout_ms);
    if (fd >= 0) return Socket.adopt(fd);
    error = errno;
  }
  _io("Socket.connect", error);
  return NULL;
}

/** Takes ownership of fd, including on failure, and creates separate File
    streams. The descriptor must name a connected TCP socket. This operation
    enables TCP_NODELAY. Raises: `<io-fail>` on a host failure. */
Socket Socket.adopt(int fd) {
  File input = NULL, output = NULL;
  int copy = -1;
  defer {
    if (input) input.close();
    else if (fd >= 0) close(fd);
    if (output) output.close();
    else if (copy >= 0) close(copy);
  }
  int enabled = 1;
  if (setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &enabled, sizeof(enabled)))
    _io("Socket.adopt", errno);
  String peer = _peer(fd);
  copy = dup(fd);
  if (copy < 0) _io("Socket.adopt", errno);
  input = File.fdopen(fd, "r");
  output = File.fdopen(copy, "w");
  Socket socket = Socket.new();
  *socket = (struct Socket) {
    .fd = fd, .input = input, .output = output, .peer = peer
  };
  fd = copy = -1;
  input = output = NULL;
  return socket;
}

/** Sets receive and send timeouts in milliseconds. Zero disables timeouts.
    A timed-out File operation raises `<io-fail>` with EAGAIN or EWOULDBLOCK.
    Raises: `<bad-arg>` for negative milliseconds, or `<io-fail>`. */
void Socket.set_timeout(Socket s, int ms) {
  if (ms < 0) raise %(bad-arg (operation "Socket.set_timeout"));
  struct timeval timeout = { .tv_sec = ms / 1000,
                            .tv_usec = (ms % 1000) * 1000 };
  if (setsockopt(s.fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) ||
      setsockopt(s.fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout)))
    _io("Socket.set_timeout", errno);
}

/** Flushes output and sends EOF to the peer while retaining input.
    Raises: `<io-fail>` if flushing or shutdown fails. */
void Socket.shutdown_write(Socket socket) {
  if (socket.output.flush()) _io("Socket.shutdown_write", errno);
  if (shutdown(socket.fd, SHUT_WR)) _io("Socket.shutdown_write", errno);
}

/** Returns numeric host:port text, with IPv6 in brackets. */
String Socket.peer(Socket socket) => socket.peer;

/** Closes both streams. Repeated calls are harmless. Close, like File.close,
    discards the close result; flush explicitly to report write errors. */
void Socket.close(Socket socket) {
  if (socket) _drop_socket(socket);
}

// listener setup and stopping

static int _bind(struct addrinfo *address) {
  int fd = socket(address->ai_family, SOCK_STREAM, 0);
  if (fd < 0) return -1;
  int enabled = 1, disabled = 0;
  if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &enabled, sizeof(enabled)))
    return _failed(fd);
  if (address->ai_family == AF_INET6 &&
      setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &disabled, sizeof(disabled)))
    return _failed(fd);
  /* Readiness can disappear before accept; never block past the stop poll. */
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK)) return _failed(fd);
  if (bind(fd, address->ai_addr, address->ai_addrlen) || listen(fd, SOMAXCONN))
    return _failed(fd);
  return fd;
}

static int _bound_port(int fd) {
  struct sockaddr_storage address;
  socklen_t length = sizeof(address);
  if (getsockname(fd, (struct sockaddr *) &address, &length))
    _io("Listener.bind", errno);
  if (address.ss_family == AF_INET)
    return ntohs(((struct sockaddr_in *) &address)->sin_port);
  return ntohs(((struct sockaddr_in6 *) &address)->sin6_port);
}

static int _stopped(Listener listener) {
  if (x2c_thread_stopping()) x2c_thread_cancel();
  return __atomic_load_n(&listener.stopped, __ATOMIC_ACQUIRE);
}

static void _drop_listener(void *ptr) {
  Listener listener = ptr;
  if (listener.fd >= 0) close(listener.fd);
  listener.fd = -1;
}

// connection setup

static int _connect(struct addrinfo *address, int timeout_ms) {
  int fd = socket(address->ai_family, SOCK_STREAM, 0);
  if (fd < 0) return -1;
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK)) return _failed(fd);
  if (connect(fd, address->ai_addr, address->ai_addrlen)) {
    if (errno != EINPROGRESS) return _failed(fd);
    struct pollfd wait = { .fd = fd, .events = POLLOUT };
    int ready;
    do ready = poll(&wait, 1, timeout_ms ? timeout_ms : -1);
    while (ready < 0 && errno == EINTR);
    if (!ready) { errno = ETIMEDOUT; return _failed(fd); }
    if (ready < 0) return _failed(fd);
    int error = 0;
    socklen_t size = sizeof(error);
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size))
      return _failed(fd);
    if (error) { errno = error; return _failed(fd); }
  }
  if (fcntl(fd, F_SETFL, flags)) return _failed(fd);
  return fd;
}

static String _peer(int fd) {
  struct sockaddr_storage address;
  socklen_t size = sizeof(address);
  if (getpeername(fd, (struct sockaddr *) &address, &size))
    _io("Socket.peer", errno);
  char host[NI_MAXHOST], port[NI_MAXSERV];
  int status = getnameinfo(
    (struct sockaddr *) &address, size, host, sizeof(host),
    port, sizeof(port), NI_NUMERICHOST | NI_NUMERICSERV);
  if (status) _io("Socket.peer", status == EAI_SYSTEM ? errno : EINVAL);
  return address.ss_family == AF_INET6
    ? %"[$host]:$port" : %"$host:$port";
}

static Socket Socket.new(void) =>
  Scope.malloc_finalized(sizeof(struct Socket), _drop_socket);

static void _drop_socket(void *ptr) {
  Socket socket = ptr;
  if (socket.input) socket.input.close();
  if (socket.output) socket.output.close();
  socket.input = socket.output = NULL;
  socket.fd = -1;
}

// native failures and process setup

static void _port(int port, String operation) {
  if (port < 0 || port > 65535)
    raise %(bad-arg (operation $operation) (port $port));
}

static struct addrinfo *_resolve(String host, int port, int flags) {
  struct addrinfo hints;
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_ADDRCONFIG | flags;
  struct addrinfo *addresses = NULL;
  char service[16];
  snprintf(service, sizeof(service), "%d", port);
  int status = getaddrinfo(host, service, &hints, &addresses);
  if (status == EAI_SYSTEM) _io("getaddrinfo", errno);
  if (status) raise %(not-found (operation "getaddrinfo") (host $host));
  return addresses;
}

static int _failed(int fd) {
  int error = errno;
  close(fd);
  errno = error;
  return -1;
}

static void _io(String operation, int error) {
  raise %(io-fail (operation $operation) (errno $error));
}

static void _ignore_sigpipe(void) {
  int error = pthread_once(&sigpipe_once, _set_sigpipe);
  if (error) _io("SIGPIPE", error);
}

static void _set_sigpipe(void) { signal(SIGPIPE, SIG_IGN); }
