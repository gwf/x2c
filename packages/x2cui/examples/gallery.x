/*  gallery.x -- CUI's component gallery, in x2c.

    This is a port of CUI's own gallery (examples/gallery_ui.c and
    examples/gallery_more.c in CUI's source): the same pages, sections,
    and layout, with each page in a file under gallery/. Read a page
    beside its C original to compare the two forms.

      gallery              browse the pages in a window
      gallery --shots DIR  draw every page off screen to DIR/NN-NAME.png

    The window follows CUI's: Ctrl or Command K opens the command palette,
    and J switches between light and dark.
*/

#include "path.x"
#include "gallery/state.x"
#include "gallery/overview.x"
#include "gallery/buttons.x"
#include "gallery/inputs.x"
#include "gallery/selection.x"
#include "gallery/navigation.x"
#include "gallery/overlays.x"
#include "gallery/feedback.x"
#include "gallery/data.x"
#include "gallery/charts.x"

// In the order of the PAGE_ constants.
static Page pages[] = {
  { "Overview", CUI_ICON_LAYOUT_DASHBOARD, page_overview },
  { "Buttons", CUI_ICON_ZAP, page_buttons },
  { "Inputs", CUI_ICON_TYPE, page_inputs },
  { "Selection", CUI_ICON_SLIDERS_HORIZONTAL, page_selection },
  { "Navigation", CUI_ICON_COMPASS, page_navigation },
  { "Overlays", CUI_ICON_LAYERS, page_overlays },
  { "Feedback", CUI_ICON_BELL, page_feedback },
  { "Data display", CUI_ICON_DATABASE, page_data },
  { "Charts", CUI_ICON_CHART_LINE, page_charts },
};

static int page_total(void) => sizeof pages / sizeof *pages;

static void set_theme(Ui ui, Gallery g, bool dark) {
  g.dark = dark;
  ui.set_theme(dark ? CUI_THEME_DARK : CUI_THEME_LIGHT);
}

static void go_to(Ui ui, Gallery g, int page) {
  g.page = page;
  g.drawer = false;
  ui.scroll_to("main", 0);
}

// One accent swatch: a ring when it is the chosen one.
typedef struct Swatch {
  cui_color color;
  bool selected;
} Swatch;

static void paint_swatch(Ui ui, cui_rect area, void *user) {
  Swatch *swatch = user;
  cui_vec2 centre = { area.x + area.w / 2, area.y + area.h / 2 };
  if (swatch.selected)
    ui.draw_circle(centre, area.w / 2, ui.color_of(CUI_COLOR_FOREGROUND));
  ui.draw_circle(centre, area.w / 2 - (swatch.selected ? 2.0f : 0.0f),
                 ui.color_of(CUI_COLOR_SURFACE_MUTED));
  ui.draw_circle(centre, area.w / 2 - 4, swatch.color);
}

static void accent_row(Ui ui, Gallery g) {
  static const unsigned colors[CUI_ACCENT_COUNT] = {
    0x555555, 0x7747ff, 0x0562ef, 0x00864b, 0xf3ad20, 0xc25300, 0xd1403a,
    0xd23286 };
  $cui.row(ui, { .justify = CUI_JUSTIFY_BETWEEN }) {
    for (int accent = 0; accent < CUI_ACCENT_COUNT; accent++) {
      Swatch swatch = { CUI_RGB(colors[accent]), g.accent == accent };
      // The canvas copies the swatch, because it paints when the frame ends.
      cui_canvas_result result = ui.canvas(
        %"accent-$accent", CUI_PX(22), CUI_PX(22), paint_swatch, &swatch,
        sizeof swatch);
      ui.tooltip(cui_accent_name((cui_accent) accent));
      if (result.clicked) {
        g.accent = accent;
        ui.set_accent((cui_accent) accent);
      }
    }
  }
}

// The page list: a column beside the page, or the body of a drawer.
static void sidebar(Ui ui, Gallery g, bool drawer) {
  $cui.column(ui, {
      .width = drawer ? CUI_FILL : CUI_PX(240), .height = CUI_FILL,
      .bg = drawer ? CUI_TRANSPARENT : CUI_COLOR_SURFACE_MUTED,
      .pad = drawer ? 0 : 12, .gap = 2 }) {
    if (!drawer) $cui.row(ui, { .gap = 10, .pad_x = 8, .pad_top = 6,
                                .pad_bottom = 18 }) {
      $cui.box(ui, { .width = CUI_PX(28), .height = CUI_PX(28), .radius = 9,
                     .bg = CUI_COLOR_FOREGROUND, .dir = CUI_STACK,
                     .align = CUI_ALIGN_CENTER,
                     .justify = CUI_JUSTIFY_CENTER })
        ui.text("C", { .font = CUI_FONT_DISPLAY, .size = 16,
                       .color = CUI_COLOR_BACKGROUND, .line_height = 1.0f });
      ui.text("CUI", { .font = CUI_FONT_MEDIUM, .size = 15, .nowrap = true });
      ui.spacer();
      // x2c reads a C macro constant as a value only when its type is given.
      int major = CUI_VERSION_MAJOR, minor = CUI_VERSION_MINOR;
      ui.badge(%"v$major.$minor", { .size = CUI_SIZE_SM });
    }
    $cui.scroll(ui, { .id = "nav", .height = CUI_FILL, .gap = 2 }) {
      ui.nav_section("Components");
      for (int page = 0; page < page_total(); page++) {
        if (page == PAGE_COUNT) {
          ui.gap(10);
          ui.nav_section("Extended");
        }
        if (ui.nav_item(pages[page].name, {
              .icon = pages[page].icon, .selected = g.page == page,
              .group = "pages" }))
          go_to(ui, g, page);
      }
    }
    $cui.column(ui, { .gap = 12, .pad = 8 }) {
      static const char *mode_icons[] = { CUI_ICON_SUN, CUI_ICON_MOON };
      int mode = g.dark;
      if (ui.segmented("theme", %("Light" "Dark"), mode, {
            .full_width = true, .icons = mode_icons, .size = CUI_SIZE_SM }))
        set_theme(ui, g, mode == 1);
      accent_row(ui, g);
    }
  }
}

static void dialogs(Ui ui, Gallery g) {
  $cui.dialog(ui, "Edit profile", g.dialog_open, {
      .description = "Changes are visible to your team." }) {
    ui.input("dlg-name", g.name, { .label = "Name" });
    ui.input("dlg-email", g.email, { .label = "Email",
                                     .icon = CUI_ICON_MAIL });
    ui.switch("Public profile", g.wifi, {});
    $cui.dialog_footer(ui) {
      if (ui.button("Cancel", {})) g.dialog_open = false;
      if (ui.button("Save changes", { .variant = CUI_BUTTON_PRIMARY })) {
        g.dialog_open = false;
        ui.toast("Profile updated", { .tone = CUI_TONE_SUCCESS });
      }
    }
  }
  $cui.dialog(ui, "Delete this project?", g.confirm_open, {
      .description = "This removes the project and its history for "
                     "everyone. You cannot undo this.",
      .width = 400 })
  $cui.dialog_footer(ui) {
    if (ui.button("Cancel##confirm", {})) g.confirm_open = false;
    if (ui.button("Delete project", { .variant = CUI_BUTTON_DANGER })) {
      g.confirm_open = false;
      ui.toast("Project deleted", { .tone = CUI_TONE_DANGER,
                                    .action = "Undo" });
    }
  }
  $cui.sheet(ui, "Notifications", g.sheet_open, {
      .description = "Choose what we tell you about." }) {
    ui.switch("Comments", g.newsletter, {
      .description = "When someone replies to you." });
    ui.switch("Mentions", g.wifi, {
      .description = "When someone mentions you." });
    ui.switch("Weekly digest", g.bluetooth, {
      .description = "A summary every Monday." });
    ui.separator();
    ui.label("Recent");
    ui.list_item("Jonas commented on Release 1.0", {
      .avatar = "Jonas Berg", .subtitle = "2 minutes ago" });
    ui.list_item("Priya invited you to Engines", {
      .avatar = "Priya Nair", .subtitle = "1 hour ago" });
  }
  static const cui_command commands[] = {
    { "Go to Overview", CUI_ICON_LAYOUT_DASHBOARD, "Navigation" },
    { "Go to Buttons", CUI_ICON_ZAP, "Navigation" },
    { "Go to Inputs", CUI_ICON_TYPE, "Navigation" },
    { "Go to Charts", CUI_ICON_CHART_LINE, "Navigation" },
    { "Toggle dark mode", CUI_ICON_MOON, "Preferences", "Ctrl J" },
    { "Change accent color", CUI_ICON_PALETTE, "Preferences" },
    { "New project", CUI_ICON_PLUS, "Actions", "Ctrl N" },
    { "Invite teammate", CUI_ICON_USER_PLUS, "Actions" },
    { "Open settings", CUI_ICON_SETTINGS, "Actions", "Ctrl ," },
  };
  switch ($cui.command_palette(ui, g.palette_open, commands)) {
    case 0: g.page = PAGE_OVERVIEW; break;
    case 1: g.page = PAGE_BUTTONS; break;
    case 2: g.page = PAGE_INPUTS; break;
    case 3: g.page = PAGE_CHARTS; break;
    case 4: set_theme(ui, g, !g.dark); break;
    case 5:
      g.accent = (g.accent + 1) % CUI_ACCENT_COUNT;
      ui.set_accent((cui_accent) g.accent);
      break;
    case 6: g.page = PAGE_FEEDBACK; break;
    case 7: g.dialog_open = true; break;
    case 8: g.sheet_open = true; break;
    default: break;
  }
}

static void draw_page(Ui ui, Gallery g) {
  if (g.page >= page_total()) g.page = PAGE_OVERVIEW;
  if (g.page != PAGE_OVERVIEW)
    $cui.column(ui, { .gap = 6, .pad_bottom = 8 })
      ui.heading(pages[g.page].name, 2);
  // The page's name scopes its ids, so ids on different pages never meet.
  $cui.id_scope(ui, pages[g.page].name) pages[g.page].draw(ui, g);
}

static void draw(Ui ui, Gallery g) {
  if (!ui.wants_keyboard()) {
    if (ui.shortcut(CUI_MOD_PRIMARY, CUI_KEY_K))
      g.palette_open = !g.palette_open;
    if (ui.shortcut(CUI_MOD_PRIMARY, CUI_KEY_J)) set_theme(ui, g, !g.dark);
  }
  // Below 760 points the page list moves into a drawer behind a button.
  bool narrow = ui.viewport_size().x < 760;
  if (!narrow) g.drawer = false;
  $cui.row(ui, { .width = CUI_FILL, .height = CUI_FILL,
                 .align = CUI_ALIGN_STRETCH, .bg = CUI_COLOR_BACKGROUND }) {
    if (!narrow) {
      sidebar(ui, g, false);
      ui.separator();
    }
    $cui.scroll(ui, { .id = "main", .width = CUI_FILL, .fade_edges = true })
    $cui.row(ui, { .justify = CUI_JUSTIFY_CENTER, .align = CUI_ALIGN_START })
    $cui.column(ui, { .width = CUI_FILL, .max_width = 920,
                      .pad_x = narrow ? 16 : 40, .pad_top = narrow ? 12 : 36,
                      .pad_bottom = 64, .gap = 20 }) {
      if (narrow) $cui.row(ui, { .gap = 8, .width = CUI_FILL }) {
        if (ui.icon_button(CUI_ICON_MENU, { .tooltip = "Components" }))
          g.drawer = true;
        ui.text("CUI", { .font = CUI_FONT_MEDIUM, .size = 15 });
      }
      draw_page(ui, g);
    }
  }
  $cui.sheet(ui, "CUI", g.drawer, { .side = CUI_SIDE_LEFT, .size = 280 })
    sidebar(ui, g, true);
  dialogs(ui, g);
}

/* Draws every page off screen, on a surface tall enough to show a whole
   page. A few frames settle layout, fonts, and opening animations before
   each page is written. */
static int shoot(Gallery g, Path directory) {
  directory.make_dirs();
  int empty = 0;
  for (int page = 0; page < page_total(); page++) {
    Offscreen screen = auto Offscreen.open(1240, 2400);
    g.page = page;
    for (int frame = 0; frame < 6; frame++) {
      screen.begin();
      draw(screen.ui(), g);
      screen.end();
    }
    String name = pages[page].name.lower().replace(" ", "-");
    screen.write_png(directory.join(String.format("%02d-%s.png", page + 1,
                                                  name)));
    if (!screen.commands()) empty++;
  }
  printf("%d pages drawn to %s, %d empty\n", page_total(), directory, empty);
  return empty ? 1 : 0;
}

int main(int argc, char **argv) {
  Gallery g = Gallery.new();
  if (argc == 3 && !strcmp(argv[1], "--shots")) return shoot(g, argv[2]);

  App app = auto App.open({ .title = "CUI Gallery", .width = 1240,
                            .height = 820, .min_width = 720,
                            .min_height = 480 });
  while (app.frame()) draw(app.ui(), g);
  return 0;
}
