/*  orders.x -- A table of recent orders in a window.

    The table takes its columns as a Map literal of titles and widths,
    sorts its rows by the column whose header was clicked, and selects the
    row that is clicked. Its cells hold text, an avatar, and a badge.

      orders                    open a window
      orders --shot IMAGE.png   draw the table off screen
*/

import "x2cui" with App, Offscreen, TextField, Ui;

class Order {
  String id, customer, email, date, status, price;
  cui_tone tone;
} *;

// A row is: id, customer, email, date, status, price, tone.
void Order.init(Order o, List row) {
  o.id = row[0];
  o.customer = row[1];
  o.email = row[2];
  o.date = row[3];
  o.status = row[4];
  o.price = row[5];
  o.tone = (int) row[6];
}

// What the table sorts by in `column`; the price sorts as a number.
Var Order.sort_key(Order o, int column) {
  switch (column) {
    case 0: return o.id;
    case 1: return o.customer;
    case 3: return o.status;
    case 4: return atof(o.price[1:].replace(",", ""));
  }
  return o.date;
}

static List rows = %(
  ("#3021" "Nora Lindqvist" "nora@lindqvist.se" "Nov 5" "Paid" "\$184.20" 2)
  ("#3020" "Kwame Asante" "kwame@asante.co" "Nov 5" "Pending" "\$42.75" 3)
  ("#3019" "Hana Novak" "hana@novak.cz" "Nov 4" "Paid" "\$318.40" 2)
  ("#3018" "Felix Moreau" "felix@moreau.fr" "Nov 4" "Refunded" "\$96.00" 4)
  ("#3017" "Iris Coleman" "iris@coleman.org" "Nov 3" "Paid" "\$471.15" 2)
  ("#3016" "Ravi Shah" "ravi@shah.in" "Nov 3" "Paid" "\$1,236.80" 2));

static Array orders;

typedef struct Dashboard {
  cui_table_sort sort;
  Order selected;        // NULL when no row is selected
  TextField search;
  int page;
} Dashboard;

static int matches(Order o, TextField search) {
  String needle = search.text();
  return o.customer.contains(needle) || o.id.contains(needle);
}

static void recent_orders(Ui ui, Dashboard &s) {
  List shown = orders.list()
    .filter(%!(Order o) => matches(o, s.search))
    .sort_by(%!(Order o) => o.sort_key(s.sort.column));
  if (s.sort.descending) shown = shown.reverse();

  ui.card (gap: 14) {
    ui.row () {
      ui.column (gap: 2, width: fill) {
        ui.label("Recent orders");
        ui.text("Newest first", size: 12, color: text_secondary);
      }
      ui.button("View all", variant: ghost, icon_right: arrow_right, size: sm);
    }

    ui.table ("orders", sort: &s.sort, selectable: true,
              columns: {"Order": 90, "Customer": fill, "Date": unsorted(90),
                        "Status": 120, "Amount": right(110)})
    ui.each (Order o in shown, key: o.id)
    ui.table_row (row, selected: s.selected == o) {
      if (row.clicked) s.selected = o;
      ui.cell_text(o.id);
      ui.cell () {
        ui.avatar(o.customer, size: 28);
        ui.column (gap: 0, width: fill) {
          ui.text(o.customer, font: medium, nowrap: true);
          ui.text(o.email, size: 12, color: text_secondary, nowrap: true);
        }
      }
      ui.cell_text(o.date);
      ui.cell () ui.badge(o.status, tone: o.tone, dot: true);
      ui.cell_text(o.price);
    }

    ui.row (wrap: true, gap: 8, width: fill) {
      ui.box (width: fill, min_width: 200)
        ui.text(%"Showing 1 to $(shown.len()) of 1,286 orders",
                size: 12, color: text_secondary);
      ui.pagination("pages", s.page, 215);
    }
  }
}

static void draw(Ui ui, Dashboard &s) {
  ui.column (width: fill, height: fill, pad: 20, bg: background)
    recent_orders(ui, s);
}

// The table sorted by amount, largest first, with the third row selected.
static int shot(Dashboard &s, String image) {
  s.sort.column = 4;
  s.sort.descending = true;
  s.selected = orders[2];
  Offscreen screen = auto Offscreen.open(760, 560);
  // The second and third frames settle layout and opening animations.
  for (int frame = 0; frame < 3; frame++) {
    screen.begin();
    draw(screen.ui(), s);
    screen.end();
  }
  screen.write_png(image);
  printf("%s: %d draw commands\n", image, screen.commands());
  return screen.commands() ? 0 : 1;
}

int main(int argc, char **argv) {
  orders = [];
  foreach (List row in rows) orders.push(Order.new(row));
  Dashboard s = { .search = TextField.new(64) };
  if (argc == 3 && !strcmp(argv[1], "--shot")) return shot(s, argv[2]);
  App app = auto App.open(title: "Orders", width: 760, height: 560,
                          min_width: 480, min_height: 360);
  while (app.frame()) draw(app.ui(), s);
  return 0;
}
