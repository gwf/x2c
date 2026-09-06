/*  datagram-report.x -- classify three loopback UDP datagrams */

import "libuv" with UvAddress, UvLoop, UvTimer, UvUdp;

#include <stdio.h>
#include <string.h>

typedef struct DatagramReport {
  UvUdp unconnected;
  UvUdp connected;
  UvUdp receiver;
  UvTimer guard;
  Bytes packets[3];
  UvAddress sources[3];
  unsigned flags[3];
  int seen[3];
  int count;
} DatagramReport;

static void received(
  UvUdp udp, Bytes packet, UvAddress source, unsigned flags, Var value) {
  DatagramReport *report = value.pointer();
  int index = (flags & UV_UDP_PARTIAL) ? 2 : packet.len() ? 0 : 1;
  if (report.count >= 3 || report.seen[index]) {
    raise %(malformed (operation "datagram-report")
            (reason "received an unexpected datagram"));
  }
  report.seen[index] = 1;
  report.count++;
  report.packets[index] = packet;
  report.sources[index] = source;
  report.flags[index] = flags;
  if (report.count == 3) {
    udp.stop().close();
    report.unconnected.close();
    report.connected.close();
    report.guard.stop();
  }
}

static void timed_out(UvTimer timer, Var value) {
  (void) timer;
  (void) value;
  raise %(timeout (operation "datagram-report")
          (reason "the loopback datagrams did not arrive"));
}

int main(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  DatagramReport report = { 0 };
  Var value = Var.new(<p48>, &report);
  report.guard = loop.timer(5000, 0, value, timed_out);
  report.receiver = loop.udp()
    .bind(UvAddress.ip4(%"127.0.0.1", 0), 0)
    .max_receive(8).receive(value, received);
  UvAddress destination = report.receiver.local_address();
  report.unconnected = loop.udp().bind(
    UvAddress.ip4(%"127.0.0.1", 0), 0
  );
  report.connected = loop.udp().bind(
    UvAddress.ip4(%"127.0.0.1", 0), 0
  ).connect(destination);
  UvAddress unconnected = report.unconnected.local_address();
  UvAddress connected = report.connected.local_address();
  UvAddress peer = report.connected.peer_address();

  unsigned char first[] = { 'b', 'u', 'i', 'l', 'd', 0, 'o', 'k' };
  Bytes binary = Bytes.new(1).append(first, sizeof(first));
  Bytes empty = Bytes.new(1);
  Bytes diagnostic = Bytes.new(1).append(
    "0123456789abcdef", 16
  );
  report.unconnected.send_bytes(destination, binary);
  report.connected.send_bytes(NULL, empty)
    .send_bytes(NULL, diagnostic);
  memset(binary, '!', binary.len());
  memset(diagnostic, '!', diagnostic.len());
  binary.free();
  empty.free();
  diagnostic.free();
  loop.run(UV_RUN_DEFAULT);

  if (report.count != 3 || report.packets[0].len() != sizeof(first) ||
      memcmp(report.packets[0], first, sizeof(first)) ||
      report.packets[1].len() != 0 || report.packets[2].len() != 8 ||
      memcmp(report.packets[2], "01234567", 8) ||
      report.flags[0] || report.flags[1] ||
      !(report.flags[2] & UV_UDP_PARTIAL) ||
      peer.port() != destination.port()) {
    raise %(malformed (operation "datagram-report")
            (reason "the datagram report changed"));
  }
  for (int i = 0; i < 3; i++) {
    int port = i ? connected.port() : unconnected.port();
    if (!report.sources[i].host().equal(%"127.0.0.1") ||
        report.sources[i].port() != port) {
      raise %(malformed (operation "datagram-report")
              (reason "the sender address changed"));
    }
  }
  printf("3 loopback datagrams: binary, empty, and 8/16-byte partial\n");
  return 0;
}
