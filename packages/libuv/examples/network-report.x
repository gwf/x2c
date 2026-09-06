/*  network-report.x -- resolve localhost and exchange binary TCP payloads */

import "libuv" with UvAddress, UvLookup, UvLoop, UvTcp, UvTimer;

#include <stdio.h>
#include <string.h>

enum { CLIENTS = 3 };

typedef struct NetworkState NetworkState;

typedef struct PeerState {
  NetworkState *network;
  UvTcp tcp;
  Bytes received;
  int client;
  int eof;
} PeerState;

struct NetworkState {
  UvLoop loop;
  UvTcp listener;
  UvTimer guard;
  PeerState clients[CLIENTS];
  PeerState servers[CLIENTS];
  int accepted;
  int complete;
  size_t echoed;
};

static void read_peer(UvTcp tcp, Bytes chunk, Var value) {
  PeerState *peer = value.pointer();
  if (!chunk) {
    peer.eof = 1;
    tcp.shutdown_write();
    if (peer.client && ++peer.network.complete == CLIENTS) {
      peer.network.listener.close();
      peer.network.guard.stop();
    }
    return;
  }
  peer.received = peer.received.append(chunk, chunk.len());
  if (!peer.client) tcp.write_bytes(chunk);
  else peer.network.echoed += chunk.len();
}

static void connected(UvTcp tcp, Var value) {
  PeerState *peer = value.pointer();
  unsigned char payload[] = { 'c', (unsigned char) ('0' + peer.client),
                              0, 'x', '2', 'c' };
  Bytes bytes = Bytes.new(1).append(payload, sizeof(payload));
  tcp.read(value, read_peer).write_bytes(bytes).shutdown_write();
  bytes.free();
}

static void accepted(UvTcp listener, UvTcp tcp, Var value) {
  NetworkState *network = value.pointer();
  PeerState *peer = &network.servers[network.accepted++];
  peer.network = network;
  peer.tcp = tcp;
  peer.received = Bytes.new(1);
  tcp.read(Var.new(<p48>, peer), read_peer);
}

static void timed_out(UvTimer timer, Var value) {
  (void) timer;
  (void) value;
  raise %(timeout (operation "network-report")
          (reason "the loopback exchange did not finish"));
}

static void resolved(UvLookup lookup, Var value) {
  NetworkState *network = value.pointer();
  UvAddress host = NULL;
  for (int i = 0; i < (int) lookup.count(); i++) {
    if (lookup.address(i).family() == AF_INET) {
      host = lookup.address(i);
      break;
    }
  }
  if (!host) raise %(missing (operation "network-report")
                     (reason "localhost has no IPv4 address"));

  network.listener = network.loop.tcp().bind(UvAddress.ip4(host.host(), 0), 0);
  network.listener.listen(CLIENTS + 1, value, accepted);
  UvAddress address = network.listener.local_address();
  for (int i = 0; i < CLIENTS; i++) {
    PeerState *peer = &network.clients[i];
    peer.network = network;
    peer.client = i + 1;
    peer.received = Bytes.new(1);
    peer.tcp = network.loop.tcp().connect(
      UvAddress.ip4(address.host(), address.port()),
      Var.new(<p48>, peer), connected
    );
  }
}

int main(void) {
  UvLoop loop = UvLoop.new();
  defer loop.free();
  NetworkState network = { .loop = loop };
  Var state = Var.new(<p48>, &network);
  network.guard = loop.timer(5000, 0, state, timed_out);
  loop.resolve(%"localhost", %"0", state, resolved);
  loop.run(UV_RUN_DEFAULT);

  for (int i = 0; i < CLIENTS; i++) {
    PeerState *client = &network.clients[i];
    PeerState *server = &network.servers[i];
    client.tcp.close();
    server.tcp.close();
    client.received.free();
    server.received.free();
  }
  loop.run(UV_RUN_DEFAULT);
  printf("%d clients, %zu bytes echoed, %d EOFs\n",
         network.complete, network.echoed, network.complete * 2);
  return 0;
}
