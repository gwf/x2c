#pragma once

/*  controls.x -- scenes for selection controls, text and number
    inputs, pickers, navigation, menus, popovers, images, dialogs, sheets,
    notifications, and status displays
*/

#include <math.h>

#include "scene.x"

static TextField full_name, email, password, bio, query;

#define PHOTO_WIDTH 800
#define PHOTO_HEIGHT 500

static unsigned char photo_pixels[PHOTO_WIDTH * PHOTO_HEIGHT * 4];

static unsigned char channel(float value) =>
  (unsigned char) (fminf(1, fmaxf(0, value)) * 255);

// A landscape: a sky with a sun over hazy hills and near fields.
static void paint_photo(void) {
  for (int y = 0; y < PHOTO_HEIGHT; y++) {
    for (int x = 0; x < PHOTO_WIDTH; x++) {
      float fx = (float) x / PHOTO_WIDTH, fy = (float) y / PHOTO_HEIGHT;
      float r = 0.56f + fy * 0.34f, g = 0.72f + fy * 0.2f;
      float b = 0.88f + fy * 0.06f;
      float sun = (fx - 0.72f) * (fx - 0.72f) * 15.4f +
                  (fy - 0.24f) * (fy - 0.24f) * 6.0f;
      if (sun < 0.024f) { r = 1.0f; g = 0.97f; b = 0.86f; }
      float far = 0.5f + 0.1f * sinf(fx * 6.0f + 0.6f) +
                  0.03f * sinf(fx * 23.0f);
      float near = 0.68f + 0.06f * sinf(fx * 4.0f + 2.1f) +
                   0.02f * sinf(fx * 31.0f);
      if (fy > far) { r = 0.5f; g = 0.6f; b = 0.62f - fy * 0.08f; }
      if (fy > near) {
        r = 0.3f - (fy - near) * 0.2f;
        g = 0.45f - (fy - near) * 0.25f;
        b = 0.3f;
      }
      unsigned char *pixel = photo_pixels + (y * PHOTO_WIDTH + x) * 4;
      pixel[0] = channel(r);
      pixel[1] = channel(g);
      pixel[2] = channel(b);
      pixel[3] = 255;
    }
  }
}

static void prepare(void) {
  full_name = TextField.new(64);
  full_name.set("Priya Nair");
  email = TextField.new(96);
  password = TextField.new(64);
  password.set("hunter");
  bio = TextField.new(512);
  bio.set("Designer in Copenhagen. I draw interfaces and the occasional "
          "map.");
  query = TextField.new(64);
  query.set("Invoice");
  paint_photo();
}

/* Returns the photo's texture in `ui`. A texture belongs to one `Ui`, so
   it is kept in that `Ui`'s state and created on first use. */
static cui_texture photo(Ui ui) {
  cui_texture *texture = ui.state(ui.make_id("photo"), sizeof *texture);
  if (!*texture)
    *texture = ui.image_create(PHOTO_WIDTH, PHOTO_HEIGHT, photo_pixels);
  return *texture;
}

/* Tests whether `ui` draws `name` for the first time, so a scene can open
   an overlay once and let it close afterwards. */
static bool first_frame(Ui ui, String name) {
  bool *seen = ui.state(ui.make_id(name), sizeof *seen);
  bool first = !*seen;
  *seen = true;
  return first;
}

static void scene_segmented(Ui ui) {
  static int view = 1, size = 0;
  static const char *icons[] = { CUI_ICON_LIST, CUI_ICON_LAYOUT_DASHBOARD,
                                 CUI_ICON_CALENDAR };
  ui.segmented("view", %("List" "Board" "Calendar"), view,
               icons: icons);
  ui.segmented("size", %("Small" "Medium" "Large"), size,
               size: CUI_SIZE_SM);
  ui.text(%"Showing the $(view == 0 ? "list" : view == 1 ? "board"
          : "calendar") view.", color: CUI_COLOR_TEXT_MUTED);
}

static void scene_checkbox(Ui ui) {
  static bool news = true, marketing = false, all = true, archived = false;
  ui.checkbox("Email notifications", news,
              description: "Product news, monthly.");
  ui.checkbox("Marketing", marketing);
  ui.checkbox("Select all files", all, indeterminate: true);
  ui.checkbox("Include archived", archived, disabled: true);
}

static void scene_switch(Ui ui) {
  static bool wifi = true, sync = false, airplane = false;
  ui.column (gap: 14, width: CUI_PX(320)) {
    ui.switch("Wi-Fi", wifi, description: "Join known networks.");
    ui.switch("Sync over cellular", sync);
    ui.switch("Airplane mode", airplane, disabled: true);
  }
}

static void scene_radio(Ui ui) {
  static int plan = 1;
  ui.label("Billing period");
  ui.radio("Monthly", plan, 0, description: "$12 a month.");
  ui.radio("Yearly", plan, 1, description: "$120 a year, two months "
                                             "free.");
  ui.radio("Lifetime", plan, 2, disabled: true);
}

static void scene_slider(Ui ui) {
  static float volume = 64, brightness = 40, zoom = 1.5f;
  ui.column (gap: 20, width: CUI_PX(420)) {
    ui.slider("Volume", volume, 0, 100, show_value: true);
    ui.slider("Brightness", brightness, 0, 100,
              step: 10, show_value: true, format: "%.0f%%");
    ui.slider("Zoom", zoom, 0.5f, 4, show_value: true,
                                      format: "%.1fx");
  }
}

static void scene_chip(Ui ui) {
  static bool picked[] = { true, false, true, false, false };
  List teams = %("Design" "Engineering" "Marketing" "Sales" "Support");
  ui.label("Teams");
  ui.row (gap: 8, wrap: true, width: CUI_PX(420)) {
    int i = 0;
    foreach (String team in teams) {
      ui.chip(team, picked[i]);
      i++;
    }
  }
  ui.chip("Starred", picked[4], icon: CUI_ICON_STAR);
}

static void scene_input(Ui ui) {
  ui.column (gap: 14, width: CUI_PX(360)) {
    ui.input("name", full_name, label: "Name");
    ui.input("email", email, label: "Email", icon: CUI_ICON_MAIL,
                             placeholder: "you@company.com",
                             hint: "Used to sign in and for receipts.");
    ui.input("password", password, label: "Password", password: true,
                                   error: "Use 8 or more characters.");
  }
}

static void scene_textarea(Ui ui) {
  ui.column (width: CUI_PX(440))
    ui.textarea("bio", bio, label: "Bio", height: 90,
                            hint: "Shown on your profile.");
}

static void scene_search(Ui ui) {
  List invoices = %("Invoice 1042, Northwind" "Invoice 1043, Contoso"
                    "Receipt 88, Fabrikam" "Invoice 1044, Litware");
  ui.column (gap: 10, width: CUI_PX(360)) {
    ui.search("q", query, placeholder: "Search documents");
    String term = query.text();
    foreach (String name in invoices)
      if (name.contains(term)) ui.text(name);
  }
}

static void scene_number(Ui ui) {
  static double seats = 5, price = 12.5, weight = 2.4;
  ui.row (gap: 16, align: CUI_ALIGN_END) {
    ui.number("seats", seats, 1, 50, label: "Seats",
                                     width: CUI_PX(140));
    ui.number("price", price, 0, 1000, label: "Price", step: 0.5,
                                       decimals: 2, suffix: "USD",
                                       width: CUI_PX(160));
    ui.number("weight", weight, 0, 50, label: "Weight", step: 0.1,
                                       decimals: 1, suffix: "kg",
                                       width: CUI_PX(140));
  }
}

static void scene_select(Ui ui) {
  static int country = 1, zone = -1;
  ui.row (gap: 16, align: CUI_ALIGN_END) {
    ui.select("country", %("Canada" "Denmark" "Germany" "Japan" "Kenya"),
              country, label: "Country", width: CUI_PX(200));
    ui.select("zone", %("Pacific" "Eastern" "Central Europe" "Tokyo"),
              zone, label: "Time zone", placeholder: "Choose one",
                    searchable: true, width: CUI_PX(220));
  }
}

static void scene_date_picker(Ui ui) {
  static cui_date due = { 2026, 11, 20 }, start = { 0, 0, 0 };
  ui.row (gap: 16, align: CUI_ALIGN_END) {
    ui.date_picker("due", due, label: "Due date", width: CUI_PX(200));
    ui.date_picker("start", start, label: "Start date",
                                   placeholder: "Pick a date",
                                   width: CUI_PX(200));
  }
}

static void scene_tabs(Ui ui) {
  static int section = 0, settings = 1;
  static const char *icons[] = { CUI_ICON_USER, CUI_ICON_LOCK,
                                 CUI_ICON_CREDIT_CARD };
  ui.column (gap: 20, width: CUI_PX(520)) {
    ui.tabs("sections", %("Overview" "Analytics" "Reports" "Settings"),
            section);
    ui.tabs("settings", %("Account" "Password" "Billing"), settings,
            variant: CUI_TABS_PILL, icons: icons);
  }
}

static void scene_nav_item(Ui ui) {
  static int chosen = 0;
  ui.column (width: CUI_PX(240), pad: 12, gap: 2, radius: 12,
             bg: CUI_COLOR_SURFACE_MUTED) {
    ui.nav_section("Workspace");
    if (ui.nav_item("Inbox", icon: CUI_ICON_INBOX, badge: "12",
                             selected: chosen == 0))
      chosen = 0;
    if (ui.nav_item("Projects", icon: CUI_ICON_FOLDER,
                                selected: chosen == 1))
      chosen = 1;
    if (ui.nav_item("Calendar", icon: CUI_ICON_CALENDAR,
                                selected: chosen == 2))
      chosen = 2;
    if (ui.nav_item("Settings", icon: CUI_ICON_SETTINGS,
                                selected: chosen == 3))
      chosen = 3;
  }
}

static void scene_popover(Ui ui) {
  static bool comments = true;
  if (first_frame(ui, "share-shown")) ui.popover_open("share");
  if (ui.button("Share", icon: CUI_ICON_SHARE_2))
    ui.popover_toggle("share");
  ui.popover ("share", width: 300) {
    ui.label("Share this document");
    ui.text("Anyone with the link can view it.",
            color: CUI_COLOR_TEXT_MUTED, size: 12);
    ui.switch("Allow comments", comments);
    ui.button("Copy link", variant: CUI_BUTTON_PRIMARY,
                           icon: CUI_ICON_LINK);
  }
}

static void scene_image_viewer(Ui ui) {
  static cui_image_view view = { 1.2f, 520, 200 };
  ui.label("Drag to pan; scroll to zoom.");
  ui.image_viewer("view", photo(ui), PHOTO_WIDTH, PHOTO_HEIGHT, view,
                  height: CUI_PX(320));
}

static void scene_cropper(Ui ui) {
  static cui_rect crop = { 380, 40, 300, 300 };
  ui.label("Choose the part of the picture for your avatar.");
  ui.cropper("crop", photo(ui), PHOTO_WIDTH, PHOTO_HEIGHT, crop,
             round: true, height: CUI_PX(320));
}

/* A dropdown menu with a labelled group, shortcuts, and a dangerous item.
   CUI opens a menu only on a click or a key, so it shows closed until the
   trigger is clicked. */
static void scene_menu(Ui ui) {
  static bool pinned = true;
  ui.menu ("Options", icon: CUI_ICON_SETTINGS) {
    ui.menu_label("Project");
    ui.menu_item("Rename", icon: CUI_ICON_PENCIL, shortcut: "F2");
    ui.menu_item("Duplicate", icon: CUI_ICON_COPY,
                              shortcut: "Ctrl D");
    if (ui.menu_item("Pinned", checked: pinned)) pinned = !pinned;
    ui.menu_separator();
    ui.menu_item("Delete", icon: CUI_ICON_TRASH_2, danger: true);
  }
}

// Menu items in a popover, which a program can open itself.
static void scene_menu_item(Ui ui) {
  static int order = 0;
  if (first_frame(ui, "sort-shown")) ui.popover_open("sort");
  if (ui.button("Sort", icon: CUI_ICON_LIST))
    ui.popover_toggle("sort");
  ui.popover ("sort", width: 220, pad: 6, gap: 1) {
    ui.menu_label("Sort by");
    List orders = %("Name" "Date modified" "Size");
    int i = 0;
    foreach (String name in orders) {
      if (ui.menu_item(name, checked: order == i)) order = i;
      i++;
    }
    ui.menu_separator();
    ui.menu_item("Reverse order", shortcut: "Ctrl R");
    ui.menu_item("Group by kind", disabled: true);
  }
}

// A context menu opens on a right click over the component before it.
static void scene_context_menu(Ui ui) {
  ui.card (id: "report", hoverable: true,
           width: CUI_PX(320), pad: 16, gap: 4) {
    ui.label("Quarterly report.pdf");
    ui.text("Right-click the card for actions.",
            color: CUI_COLOR_TEXT_MUTED, size: 12);
  }
  ui.context_menu ("file") {
    ui.menu_item("Open", icon: CUI_ICON_FILE_TEXT);
    ui.menu_item("Download", icon: CUI_ICON_DOWNLOAD);
    ui.menu_separator();
    ui.menu_item("Move to trash", icon: CUI_ICON_TRASH_2,
                                  danger: true);
  }
}

// A confirmation dialog over a page, with its actions in the footer.
static void scene_dialog(Ui ui) {
  static bool open = true;
  ui.heading("Projects", 3);
  ui.skeleton(CUI_PCT(80), 14);
  ui.skeleton(CUI_PCT(60), 14);
  ui.skeleton(CUI_PCT(70), 14);
  if (ui.button("Delete", variant: CUI_BUTTON_OUTLINE)) open = true;
  ui.dialog ("Delete project?", open,
      description: "This removes the project for everyone. "
                     "You cannot undo this.",
      width: 380)
  ui.dialog_footer () {
    if (ui.button("Cancel")) open = false;
    if (ui.button("Delete project", variant: CUI_BUTTON_DANGER))
      open = false;
  }
}

static void scene_sheet(Ui ui) {
  static bool open = true, digest = true, mentions = false;
  if (ui.button("Notification settings")) open = true;
  ui.sheet ("Notifications", open,
      size: 320, description: "Choose what reaches your inbox.") {
    ui.switch("Daily digest", digest);
    ui.switch("Mentions only", mentions);
    if (ui.button("Done", variant: CUI_BUTTON_PRIMARY)) open = false;
  }
}

static void scene_toast(Ui ui) {
  if (ui.button("Save profile", variant: CUI_BUTTON_PRIMARY) ||
      first_frame(ui, "toast-shown"))
    ui.toast("Changes saved", description: "Your profile is up to date.",
                              tone: CUI_TONE_SUCCESS);
}

static void scene_alert(Ui ui) {
  ui.column (gap: 10, width: CUI_PX(560)) {
    ui.alert("Payment received",
      description: "Your invoice was paid on November 5.",
      tone: CUI_TONE_SUCCESS);
    ui.alert("Storage almost full",
      description: "You have used 92% of your plan.",
      tone: CUI_TONE_WARNING, dismissible: true);
    ui.alert("Sync failed", description: "Check your connection.",
                            tone: CUI_TONE_DANGER);
  }
}

static void scene_progress(Ui ui) {
  ui.column (gap: 18, width: CUI_PX(420)) {
    ui.progress(0.68f, label: "Uploading", show_value: true);
    ui.progress(0.92f, label: "Storage", tone: CUI_TONE_WARNING,
                       show_value: true);
    ui.progress(1, label: "Backup complete", tone: CUI_TONE_SUCCESS);
    ui.progress(5.0f / 8, height: 5);
  }
}

static void scene_badge(Ui ui) {
  ui.row (gap: 8, wrap: true) {
    ui.badge("Draft");
    ui.badge("New", tone: CUI_TONE_ACCENT);
    ui.badge("Active", tone: CUI_TONE_SUCCESS, dot: true);
    ui.badge("Pending", tone: CUI_TONE_WARNING, dot: true);
    ui.badge("Failed", tone: CUI_TONE_DANGER, dot: true);
    ui.badge("Beta", solid: true);
    ui.badge("Verified", tone: CUI_TONE_INFO, icon: CUI_ICON_CHECK);
  }
}

static void scene_avatar(Ui ui) {
  ui.row (gap: 14, align: CUI_ALIGN_CENTER) {
    ui.avatar("Jonas Berg", size: 40, status: "online");
    ui.avatar("Priya Nair", size: 40, status: "away");
    ui.avatar("Kwame Asante", size: 40);
    ui.avatar("Landscape", size: 40, image: photo(ui),
                           square: true);
    ui.avatar_group(%("Rosa Delgado" "Daniel Mensah" "Elif Kaya"
                      "Ben Carter" "Omar Haddad"), 3, 32);
  }
}

static Scene controls_scenes[] = {
  { "segmented", scene_segmented },
  { "checkbox", scene_checkbox },
  { "switch", scene_switch },
  { "radio", scene_radio },
  { "slider", scene_slider },
  { "chip", scene_chip },
  { "input", scene_input },
  { "textarea", scene_textarea },
  { "search", scene_search },
  { "number", scene_number },
  { "select", scene_select },
  { "date_picker", scene_date_picker },
  { "tabs", scene_tabs },
  { "nav_item", scene_nav_item },
  { "popover", scene_popover },
  { "image_viewer", scene_image_viewer },
  { "cropper", scene_cropper },
  { "menu", scene_menu },
  { "context_menu", scene_context_menu },
  { "menu_item", scene_menu_item },
  { "dialog", scene_dialog },
  { "dialog_footer", scene_dialog },
  { "sheet", scene_sheet },
  { "toast", scene_toast },
  { "alert", scene_alert },
  { "progress", scene_progress },
  { "badge", scene_badge },
  { "avatar", scene_avatar },
};

Family controls_family(void) {
  prepare();
  return (Family){ "Controls, inputs, and overlays", controls_scenes,
                   sizeof controls_scenes / sizeof *controls_scenes };
}
