---
slug: destructuring
section: power
home: true
order: 3
tab: destructuring
title: Tuple trouble.
---

```x2c
~int main(void) {
  Array orders = [
    %(tea 2 "Ada"),
    %(coffee 1 "Grace"),
    %(tea 1 "Linus")
  ];

  // Give each field a typed name.
  foreach (List order in orders) {
    (Symbol item, int count, String who) = order;
    printf("%s wants %d %s\n", who, count, item.str());
  }

  // Select a shape and bind its fields in the condition.
  foreach (List order in orders)
    if (order ~= %(tea ?(int n) ?(String who)) && n > 1)
      puts(%"$who is thirsty");
~  return 0;
~}
```

Destructuring gives each position a typed name. A pattern condition selects tea orders and binds their fields for the rest of the condition and its body.
