#pragma once

/*  state.x -- what the gallery's pages share

    The gallery is a port of CUI's own gallery, examples/gallery_ui.c in
    CUI's source, page for page. Every page reads and changes one Gallery,
    the program's whole state.
*/

import "x2cui" with App, Offscreen, TextField, Ui;

// The first pages, in the order of the sidebar.
enum {
  PAGE_OVERVIEW, PAGE_BUTTONS, PAGE_INPUTS, PAGE_SELECTION, PAGE_NAVIGATION,
  PAGE_OVERLAYS, PAGE_FEEDBACK, PAGE_DATA, PAGE_CHARTS, PAGE_COUNT
};

typedef struct Gallery {
  int page;
  // buttons
  bool loading;
  int seg_view, seg_size;
  // inputs
  TextField name, email, password, search, bio, amount_text;
  double quantity;
  cui_date date;
  cui_color color;
  // selection
  bool terms, newsletter, marketing, wifi, bluetooth, airplane;
  int plan;
  float volume, brightness, lo, hi;
  int rating;
  bool chips[6];
  int framework;
  int plan_card;
  TextField tags, otp;
  int country;
  // navigation
  int tab, tab2, page_index, step;
  // overlays
  bool dialog_open, sheet_open, palette_open, confirm_open;
  bool drawer;             // the page list on a narrow window
  // data
  bool acc[3];
  bool tree_src, tree_ui, tree_assets;
  int selected_row;
  cui_table_sort sort;
  int selected_file;
  ArrayInt task_order;
  // app
  bool dark;
  int accent;
} *Gallery;

// A page of the gallery, as the sidebar lists it.
typedef struct Page {
  String name;
  String icon;
  void (*draw)(Ui ui, Gallery g);
} Page;

/** Returns a Gallery with the values every page starts from. */
Gallery Gallery.new(void) {
  Gallery g = xcalloc(1, sizeof *g);
  g.page = PAGE_OVERVIEW;
  g.name = TextField.new(64);
  g.email = TextField.new(96);
  g.password = TextField.new(64);
  g.search = TextField.new(64);
  g.bio = TextField.new(512);
  g.amount_text = TextField.new(32);
  g.tags = TextField.new(256);
  g.otp = TextField.new(8);
  g.name.set("Maya Okafor");
  g.email.set("maya@fieldwork.studio");
  g.bio.set("Mathematician and writer. I like engines that compute and "
            "interfaces that stay out of the way.");
  g.quantity = 3;
  g.date = (cui_date){ 2026, 11, 14 };
  g.color = CUI_RGB(0x7747ff);
  g.newsletter = true;
  g.wifi = true;
  g.plan = 1;
  g.volume = 64;
  g.brightness = 40;
  g.lo = 20;
  g.hi = 75;
  g.rating = 4;
  g.chips[0] = true;
  g.chips[2] = true;
  g.framework = -1;
  g.plan_card = 1;
  g.tags.set("design, c99, native");
  g.otp.set("418");
  g.country = 2;
  g.step = 1;
  g.acc[0] = true;
  g.tree_src = true;
  g.tree_ui = true;
  g.selected_row = 1;
  g.selected_file = 2;
  g.task_order = [0, 1, 2, 3, 4];
  return g;
}

/** Begins a section of a page: a heading, and a line under it when
    `description` is not NULL.
*/
void section(Ui ui, String title, String description) {
  // More room above a heading than below it, so it starts what follows.
  ui.column (gap: 4, pad_top: 18) {
    ui.heading(title, 4);
    if (description) ui.secondary(description);
  }
}
