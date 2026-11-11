#pragma once

/*  chrome.x -- scenes for compound buttons, special inputs, the
    menu bar, toolbar, and status bar, the property inspector, the log
    console, and developer tools
*/

#include "scene.x"

// Text that components edit in place, created once by prepare.
static TextField title, owner, due;
static TextField object_name, output_path;
static TextField cron, pattern, sample, url;

// The log console's storage; the app owns it and the view reads it.
static cui_log_line log_lines[64];
static char log_text[8 * 1024];
static cui_log_buffer build_log;

static TextField field(int capacity, String text) {
  TextField made = TextField.new(capacity);
  made.set(text);
  return made;
}

static void fill_build_log(void) {
  static const struct { cui_log_level level; const char *text; } lines[] = {
    { CUI_LOG_INFO, "Loading project harbor_town (412 assets)" },
    { CUI_LOG_DEBUG, "Asset cache hit rate 91.4% (376 of 412)" },
    { CUI_LOG_INFO, "Compiling shaders: 64 variants on 8 threads" },
    { CUI_LOG_WARN, "water_surface.frag:118: implicit float to half" },
    { CUI_LOG_INFO, "Shaders compiled in 2.41 s" },
    { CUI_LOG_TRACE, "gpu: uploaded 37 textures, 148.2 MB resident" },
    { CUI_LOG_INFO, "Baking navmesh for 3 regions" },
    { CUI_LOG_ERROR, "Missing material 'dock_planks_wet' on pier_03.obj" },
    { CUI_LOG_INFO, "Entering play mode" },
    { CUI_LOG_WARN, "Physics step took 21.4 ms (budget 16.6 ms)" },
    { CUI_LOG_INFO, "Autosave written to saves/slot_2.sav (1.2 MB)" },
  };
  // cui_log_init has no method;
  // the buffer, line array, and text array are C storage.
  cui_log_init(&build_log, log_lines, 64, log_text, sizeof log_text);
  double t = 14 * 3600 + 2 * 60 + 7.12;
  for (int k = 0; k < (int) (sizeof lines / sizeof *lines); k++) {
    build_log.now = t;
    build_log.append(lines[k].level, "%s", lines[k].text);
    t += 0.083 + (k % 5) * 0.217;
  }
}

static void prepare(void) {
  title = field(64, "Q3 roadmap");
  owner = field(64, "Jonas Berg");
  due = field(64, "End of September");
  object_name = field(32, "crate_large_02");
  output_path = field(128, "renders/harbor_####.png");
  cron = field(64, "30 9 * * 1-5");
  pattern = field(128, "(?<user>[\\w.]+)@(?<host>[\\w-]+)\\.\\w+");
  sample = field(1024, "Contact maya.okafor@example.com or "
                       "jonas@cui-lib.org for access.\n"
                       "Old address: priya@legacy.net\n"
                       "Support: help@example.com");
  url = field(256, "https://api.example.com/v1/orders?status=open&limit=20");
  fill_build_log();
}

static void scene_split_button(Ui ui) {
  $cui.row(ui, { .gap = 12, .wrap = true }) {
    ui.split_button("Save", %("Save as draft" "Save and publish" "Schedule"),
                    { .icon = CUI_ICON_SAVE });
    ui.split_button("Export", %("PDF" "PNG" "SVG"),
                    { .variant = CUI_BUTTON_OUTLINE,
                      .icon = CUI_ICON_DOWNLOAD });
    ui.split_button("Run", %("Run tests" "Run with coverage"),
                    { .variant = CUI_BUTTON_SECONDARY,
                      .icon = CUI_ICON_PLAY });
  }
  ui.text("The main part runs the action; the chevron opens the others.",
          { .color = CUI_COLOR_TEXT_MUTED });
}

static void scene_confirm_button(Ui ui) {
  $cui.row(ui, { .gap = 12, .wrap = true }) {
    ui.confirm_button("Delete project", { .icon = CUI_ICON_TRASH_2 });
    ui.confirm_button("Remove member", { .icon = CUI_ICON_USER,
                                         .confirm_label = "Remove Maya?",
                                         .timeout = 5 });
  }
  ui.text("The first click arms the button; a second click confirms.",
          { .color = CUI_COLOR_TEXT_MUTED });
}

static void scene_status_button(Ui ui) {
  $cui.row(ui, { .gap = 12, .wrap = true }) {
    ui.status_button("Deploy", CUI_STATUS_IDLE, { .icon = CUI_ICON_PLAY });
    ui.status_button("Save changes", CUI_STATUS_BUSY,
                     { .icon = CUI_ICON_SAVE });
    ui.status_button("Publish", CUI_STATUS_SUCCESS,
                     { .success_label = "Published" });
    ui.status_button("Sync", CUI_STATUS_ERROR,
                     { .error_label = "Sync failed",
                       .variant = CUI_BUTTON_OUTLINE });
  }
}

static void scene_user_menu(Ui ui) {
  $cui.box(ui, { .width = CUI_PX(270) })
  $cui.user_menu(ui, "Maya Okafor", { .detail = "maya@fieldwork.studio",
                                      .status = "online",
                                      .placement = CUI_PLACE_BOTTOM_START }) {
    ui.menu_item("Profile", { .icon = CUI_ICON_USER, .shortcut = "Ctrl P" });
    ui.menu_item("Billing", { .icon = CUI_ICON_CREDIT_CARD });
    ui.menu_item("Settings", { .icon = CUI_ICON_SETTINGS,
                               .shortcut = "Ctrl ," });
    ui.menu_separator();
    ui.menu_item("Log out", { .icon = CUI_ICON_LOG_OUT });
  }
}

// A muted caption in a fixed column, so the values beside it line up.
static void caption(Ui ui, String text) {
  $cui.box(ui, { .width = CUI_PX(64) }) ui.muted(text);
}

static void scene_inline_edit(Ui ui) {
  $cui.column(ui, { .gap = 10, .width = CUI_FILL }) {
    ui.inline_edit("title", title, { .font = CUI_FONT_DISPLAY, .size = 26 });
    $cui.row(ui, { .gap = 12, .align = CUI_ALIGN_CENTER }) {
      caption(ui, "Owner");
      ui.inline_edit("owner", owner, {});
    }
    $cui.row(ui, { .gap = 12, .align = CUI_ALIGN_CENTER }) {
      caption(ui, "Due");
      ui.inline_edit("due", due, {});
    }
  }
}

static void scene_scrub(Ui ui) {
  static float opacity = 80, radius = 12, blur = 24;
  $cui.row(ui, { .gap = 12, .wrap = true }) {
    ui.scrub("Opacity", opacity, 0, 100, { .suffix = "%" });
    ui.scrub("Radius", radius, 0, 48, { .step = 0.5f, .format = "%.1f",
                                        .suffix = "px" });
    ui.scrub("Blur", blur, 0, 80, { .suffix = "px",
                                    .width = CUI_PX(140) });
  }
  ui.text("Drag sideways to change a value, or click to type one.",
          { .color = CUI_COLOR_TEXT_MUTED });
}

static void scene_money_input(Ui ui) {
  static double budget = 1249.5, rate = 86;
  $cui.column(ui, { .gap = 12, .width = CUI_PX(260) }) {
    ui.money_input("budget", budget, { .label = "Monthly budget",
                                       .code = "USD",
                                       .hint = "Billed on the first" });
    ui.money_input("rate", rate, { .label = "Hourly rate",
                                   .hint = "Before tax" });
  }
}

static void scene_shortcut_recorder(Ui ui) {
  static cui_key_combo palette = { CUI_MOD_CTRL | CUI_MOD_SHIFT, CUI_KEY_P };
  static cui_key_combo search = { 0, CUI_KEY_NONE };
  $cui.column(ui, { .gap = 10 }) {
    $cui.row(ui, { .gap = 12, .align = CUI_ALIGN_CENTER }) {
      $cui.box(ui, { .width = CUI_PX(140) }) ui.label("Command palette");
      ui.shortcut_recorder("palette", palette, {});
    }
    $cui.row(ui, { .gap = 12, .align = CUI_ALIGN_CENTER }) {
      $cui.box(ui, { .width = CUI_PX(140) }) ui.label("Search files");
      ui.shortcut_recorder("search", search,
                           { .placeholder = "Record shortcut" });
    }
  }
}

static void scene_menu_bar(Ui ui) {
  static bool sidebar = true, minimap = false, wrap = true;
  $cui.card(ui, { .width = CUI_FILL, .pad = 0, .gap = 0 }) {
    $cui.menu_bar(ui, "menubar", {}) {
      $cui.menu_bar_menu(ui, "File", {}) {
        ui.menu_item("New file", { .shortcut = "Ctrl N" });
        ui.menu_item("Open", { .shortcut = "Ctrl O" });
        ui.menu_separator();
        ui.menu_item("Save", { .shortcut = "Ctrl S" });
      }
      $cui.menu_bar_menu(ui, "Edit", {}) {
        ui.menu_item("Undo", { .shortcut = "Ctrl Z" });
        ui.menu_item("Redo", { .shortcut = "Ctrl Shift Z",
                               .disabled = true });
      }
      $cui.menu_bar_menu(ui, "View", {}) {
        if (ui.menu_item("Sidebar", { .checked = sidebar }))
          sidebar = !sidebar;
        if (ui.menu_item("Minimap", { .checked = minimap }))
          minimap = !minimap;
        if (ui.menu_item("Word wrap", { .checked = wrap })) wrap = !wrap;
      }
      $cui.menu_bar_menu(ui, "Help", {}) {
        ui.menu_item("Keyboard shortcuts", { .shortcut = "Ctrl K" });
        ui.menu_item("Release notes", {});
      }
    }
    $cui.box(ui, { .pad = 16, .width = CUI_FILL })
      ui.text("Click a menu to open it. Alt or F10 focuses the bar, and "
              "the arrows move between menus.",
              { .color = CUI_COLOR_TEXT_MUTED });
  }
}

static void scene_toolbar(Ui ui) {
  static bool bold = true, italic = false, underline = false, list = true;
  $cui.card(ui, { .width = CUI_FILL, .pad = 0, .gap = 0 }) {
    $cui.toolbar(ui, "tools", {}) {
      ui.toolbar_button(CUI_ICON_PLUS, { .tooltip = "New file",
                                         .shortcut = "Ctrl N" });
      ui.toolbar_button(CUI_ICON_FOLDER_OPEN, { .tooltip = "Open" });
      ui.toolbar_button(CUI_ICON_SAVE, { .tooltip = "Save",
                                         .shortcut = "Ctrl S" });
      ui.toolbar_separator();
      ui.toolbar_button(CUI_ICON_UNDO_2, { .tooltip = "Undo" });
      ui.toolbar_button(CUI_ICON_REDO_2, { .tooltip = "Redo",
                                           .disabled = true });
      ui.toolbar_separator();
      // .toggle is a bool pointer inside an options record.
      ui.toolbar_button(CUI_ICON_BOLD, { .tooltip = "Bold", .toggle = &bold });
      ui.toolbar_button(CUI_ICON_ITALIC, { .tooltip = "Italic",
                                           .toggle = &italic });
      ui.toolbar_button(CUI_ICON_UNDERLINE, { .tooltip = "Underline",
                                              .toggle = &underline });
      ui.toolbar_button(CUI_ICON_LIST, { .tooltip = "Bulleted list",
                                         .toggle = &list });
      ui.toolbar_spacer();
      ui.toolbar_button(CUI_ICON_PLAY, { .label = "Preview" });
      ui.toolbar_button(CUI_ICON_SHARE_2, { .label = "Share" });
    }
    $cui.box(ui, { .pad = 16, .width = CUI_FILL })
      ui.text("Bold and the bulleted list are on. Items that do not fit "
              "collapse into a menu at the end.",
              { .color = CUI_COLOR_TEXT_MUTED });
  }
}

static void scene_status_bar(Ui ui) {
  static int spaces = 4;
  $cui.card(ui, { .width = CUI_FILL, .pad = 0, .gap = 0 }) {
    $cui.box(ui, { .pad = 16, .width = CUI_FILL, .height = CUI_PX(120) })
      ui.text("The status bar runs along the bottom of a window.",
              { .color = CUI_COLOR_TEXT_MUTED });
    // The bar has no fill of its own; this box gives it one.
    $cui.box(ui, { .width = CUI_FILL, .bg = CUI_COLOR_SURFACE_MUTED })
    $cui.status_bar(ui, "status", {}) {
      ui.status_bar_item("main", { .icon = CUI_ICON_GIT_BRANCH,
                                   .tooltip = "Switch branch" });
      ui.status_bar_text("Saved", { .icon = CUI_ICON_CHECK,
                                    .tone = CUI_TONE_SUCCESS });
      ui.status_bar_progress(0.62f, { .label = "Indexing 62%" });
      ui.status_bar_spacer();
      ui.status_bar_item("Ln 48, Col 17###pos", { .tooltip = "Go to line" });
      if (ui.status_bar_item(%"Spaces: $(spaces)###spaces", {}))
        spaces = spaces == 4 ? 2 : 4;
      ui.status_bar_item("UTF-8", {});
      ui.status_bar_item(NULL, { .icon = CUI_ICON_BELL,
                                 .tooltip = "Notifications" });
    }
  }
}

// Calls begin and end directly, with no block.
static void scene_inspector_begin(Ui ui) {
  static bool output_open = true;
  static int width = 1920, height = 1080, samples = 64;
  static bool denoise = true, cast = true;
  $cui.card(ui, { .width = CUI_FILL, .max_width = 460, .pad_x = 16,
                  .pad_y = 6, .gap = 0 }) {
    if (ui.inspector_begin("render", {})) {
      if (ui.inspector_group("Output", output_open)) {
        ui.prop_int("Width", width, { .min = 16, .max = 8192,
                                      .suffix = "px" });
        ui.prop_int("Height", height, { .min = 16, .max = 8192,
                                        .suffix = "px" });
        ui.prop_int("Samples", samples, { .min = 1, .max = 4096 });
        ui.prop_bool("Denoise", denoise, {});
        ui.prop_bool("Cast shadows", cast, { .checkbox = true });
        ui.prop_text("Path", output_path, {});
      }
      ui.inspector_end();
    }
  }
}

static void scene_inspector(Ui ui) {
  static bool material_open = true;
  static float roughness = 0.42f, emission = 1.6f;
  static cui_color base = { 0xC2, 0x6A, 0x3D, 255 };
  static int shader = 0;
  static bool double_sided = false;
  $cui.card(ui, { .width = CUI_FILL, .max_width = 460, .pad_x = 16,
                  .pad_y = 6, .gap = 0 })
  $cui.inspector(ui, "props", {}) {
    if (ui.inspector_group("Material", material_open)) {
      ui.prop_text("Name", object_name, {});
      ui.prop_enum("Shader", %("Standard PBR" "Unlit" "Toon" "Glass"),
                   shader, {});
      ui.prop_color("Base color", base, {});
      ui.prop_float("Roughness", roughness, { .min = 0, .max = 1,
                                              .step = 0.01f });
      ui.prop_float("Emission", emission, { .step = 0.1f,
                                            .suffix = "nits" });
      ui.prop_bool("Double sided", double_sided, {});
    }
  }
}

static void scene_log_view(Ui ui) {
  ui.log_view("log", build_log, { .height = 380, .timestamps = true });
}

static void scene_schedule_picker(Ui ui) {
  $cui.column(ui, { .gap = 10, .width = CUI_FILL, .max_width = 560 })
    ui.schedule_picker("backup", cron, { .now = 1794211200, .utc = true,
                                         .next_count = 3 });
}

static void scene_regex_tester(Ui ui) {
  ui.regex_tester("regex", pattern, sample, { .height = 110 });
}

static void scene_request_bar(Ui ui) {
  static int method = CUI_HTTP_POST;
  static bool sending = false;
  $cui.column(ui, { .gap = 12, .width = CUI_FILL }) {
    cui_request_bar_result result =
      ui.request_bar("request", method, url, { .loading = sending });
    if (result.send) sending = true;
    if (result.cancel) sending = false;
    ui.response_status(201, 0.142, 18400);
  }
}

static Scene chrome_scenes[] = {
  { "split_button", scene_split_button },
  { "confirm_button", scene_confirm_button },
  { "status_button", scene_status_button },
  { "user_menu", scene_user_menu },
  { "inline_edit", scene_inline_edit },
  { "scrub", scene_scrub },
  { "money_input", scene_money_input },
  { "shortcut_recorder", scene_shortcut_recorder },
  { "menu_bar", scene_menu_bar },
  { "menu_bar_menu", scene_menu_bar },
  { "toolbar", scene_toolbar },
  { "toolbar_button", scene_toolbar },
  { "status_bar", scene_status_bar },
  { "status_bar_text", scene_status_bar },
  { "status_bar_item", scene_status_bar },
  { "status_bar_progress", scene_status_bar },
  { "inspector_begin", scene_inspector_begin },
  { "inspector", scene_inspector },
  { "prop_float", scene_inspector },
  { "prop_int", scene_inspector_begin },
  { "prop_text", scene_inspector },
  { "prop_bool", scene_inspector },
  { "prop_enum", scene_inspector },
  { "prop_color", scene_inspector },
  { "log_view", scene_log_view },
  { "schedule_picker", scene_schedule_picker },
  { "regex_tester", scene_regex_tester },
  { "request_bar", scene_request_bar },
};

Family chrome_family(void) {
  prepare();
  return (Family){ "App chrome, properties, and developer tools",
                   chrome_scenes,
                   sizeof chrome_scenes / sizeof *chrome_scenes };
}
