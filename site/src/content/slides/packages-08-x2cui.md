---
slug: x2cui
section: packages
tab: x2cui
title: You complete me.
image: packages/x2cui-orders.png
imageAlt: Recent orders with customer avatars, payment badges, sortable columns, and pagination.
imageWidth: 760
imageHeight: 560
links:
  - label: Full source
    href: https://github.com/gwf/x2c/blob/main/packages/x2cui/examples/orders.x
  - label: Build from a checkout
    href: /docs/guide/x2cui.html
  - label: Package status
    href: https://github.com/gwf/x2c/blob/main/packages/x2cui/README.md#status
---

<!-- ignore: source excerpt; the complete example requires x2cui and its application state. -->
```x2c,ignore
import "x2cui" with App, Offscreen, TextField, Ui;

ui.table ("orders", sort: &s.sort, selectable: true,
          columns: {"Order": 90, "Customer": fill,
                    "Date": unsorted(90), "Status": 120,
                    "Amount": right(110)})
ui.each (Order o in shown, key: o.id)
ui.table_row (row, selected: s.selected == o) {
  if (row.clicked)
    s.selected = o;

  ui.cell_text(o.id);
  ui.cell () {
    ui.avatar(o.customer, size: 28);
    ui.column (gap: 0, width: fill) {
      ui.text(o.customer, font: medium, nowrap: true);
      ui.text(o.email, size: 12,
              color: text_secondary, nowrap: true);
    }
  }

  ui.cell_text(o.date);
  ui.cell ()
    ui.badge(o.status, tone: o.tone, dot: true);
  ui.cell_text(o.price);
}
```

x2cui provides an x2c interface to CUI's drawn components. Define table columns with a Map, then compose each row from text, avatars, and badges. The complete orders example sorts columns, selects rows, and draws pagination. This image comes from its off-screen renderer.

The package is experimental and source-only.
