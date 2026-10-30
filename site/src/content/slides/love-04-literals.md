---
slug: literals
section: love
tab: literals
title: Data reads the way you wrote it.
---

```x2c
~#include <assert.h>
~
int main(void) {
  Map workshop = {
    title: "Make a tiny game",
    topics: %(graphics sound games),
    venue: {
      name: "The Maker House", room: "Studio 2", seats: 24,
      address: { street: "12 Garden Lane", city: "Bristol" }
    },
    hosts: [
      { name: "Ada", role: <instructor>, skills: %(graphics games) },
      { name: "Sam", role: <mentor>, skills: %(music sound) }
    ],
    pricing: { currency: "GBP", standard: 35.0, student: 15.0 },
    bring: ["A laptop", "Headphones", "An unfinished idea"],
    sessions: [
      { title: "Draw a world", minutes: 45,
        project: { width: 320, height: 240, colors: 16 } },
      { title: "Make it move", minutes: 60,
        controls: { left: <a>, right: <d>, jump: <space> } },
      { title: "Add some sound", minutes: 30,
        audio: { channels: 2, volume: 0.75, rate: 44100 } }
    ]
  };
  ~Map venue = workshop[<venue>];
  ~Map address = venue[<address>];
  ~Array hosts = workshop[<hosts>];
  ~Map host = hosts[0];
  ~Map pricing = workshop[<pricing>];
  ~Array sessions = workshop[<sessions>];
  ~Map first = sessions[0], last = sessions[2];
  ~Map project = first[<project>], audio = last[<audio>];
  ~assert(venue[<seats>] == 24 && address[<city>] == "Bristol");
  ~assert(host[<skills>] == %(graphics games));
  ~assert(pricing[<student>] == 15.0 && pricing[<currency>] == "GBP");
  ~assert(project[<width>] == 320 && audio[<volume>] == 0.75);
  ~assert(workshop[<topics>] == %(graphics sound games));
  return 0;
}
```

One literal describes the whole workshop. Bare keys are Symbols, values are
whatever you typed, and Maps, Arrays, and Lists nest with braces, brackets,
and parentheses. No parser and no builder functions.

The shape on the screen is the shape in memory. Splice a computed value in
with `$` wherever you need one.
