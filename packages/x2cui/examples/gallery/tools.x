#pragma once

/*  tools.x -- gallery scenes for path bars, file browsers and pickers, a
    terminal, markdown, a code editor, a diff view, a node editor, docking,
    and an emoji picker
*/

#include "scene.x"
#include "path.x"

static String examples_dir;
static TextField folder, chosen, source, status;

// The terminal's output buffer, which CUI fills as text is written.
static char term_text[16 * 1024];
static cui_terminal_line term_lines[256];
static cui_terminal_buffer term;

static String code =
  "int tile_cache_find(int x, int y) {\n"
  "    for (int i = 0; i < CACHE_SLOTS; i++) {\n"
  "        if (cache[i].x == x && cache[i].y == y) {\n"
  "            cache[i].last_used = frame;\n"
  "            return i;\n"
  "        }\n"
  "    }\n"
  "    return -1;\n"
  "}\n";

/* The package's examples directory, found from the repository root or
   from the package directory. */
static String find_examples(void) {
  Path inside = "packages/x2cui/examples";
  return inside.is_dir() ? inside : "examples";
}

static void fill_terminal(void) {
  // cui_terminal_init takes a char buffer and a line array.
  cui_terminal_init(&term, term_text, sizeof term_text, term_lines, 256);
  cui_terminal_write(&term, "\x1b[2m~/x2cui $ \x1b[0mmake builds/gallery\n",
                     -1);
  cui_terminal_write(&term, "[ 33%] \x1b[32mCompiling\x1b[0m gallery.x\n", -1);
  cui_terminal_write(&term, "[ 66%] \x1b[32mCompiling\x1b[0m x2cui.x\n", -1);
  cui_terminal_write(&term, "\x1b[1mtools.x:42:9: \x1b[35mwarning:\x1b[0m"
                     "\x1b[1m unused variable 'span'\x1b[0m\n", -1);
  cui_terminal_write(&term, "[100%] \x1b[1;32mLinking builds/gallery\x1b[0m\n",
                     -1);
  cui_terminal_write(&term, "\x1b[2m~/x2cui $ \x1b[0mbuilds/gallery --shots"
                     " builds/shots\n", -1);
  cui_terminal_write(&term, "\x1b[32m17 scenes drawn\x1b[0m to builds/shots,"
                     " 0 empty\n", -1);
}

static void prepare(void) {
  examples_dir = find_examples();
  folder = TextField.new(1024);
  folder.set(examples_dir);
  chosen = TextField.new(1024);
  source = TextField.new(4096);
  source.set(code);
  status = TextField.new(256);
  status.set("Shipped the fix ");
  fill_terminal();
}

static void scene_path_bar(Ui ui) {
  static int depth = 5;
  List segments = %("x2c" "packages" "x2cui" "examples" "gallery");
  cui_path_bar_result result = ui.path_bar(
    "path", segments[:depth], { .icon = CUI_ICON_FOLDER });
  if (result.clicked >= 0) depth = result.clicked + 1;
  ui.text("Click a segment to go up, or the empty part to type a path.",
          { .color = CUI_COLOR_TEXT_MUTED });
}

static void scene_file_browser(Ui ui) {
  cui_file_browser_result result = ui.file_browser(
    "files", folder, { .height = CUI_PX(360) });
  ui.text(result.selected ? %"Selected $(result.selected)"
                          : %"In $(folder.text())",
          { .color = CUI_COLOR_TEXT_MUTED, .size = 12 });
}

static void scene_terminal(Ui ui) {
  cui_terminal_result result = ui.terminal(
    "term", term, { .height = 360, .prompt = "~/x2cui $ " });
  if (result.command && result.command[0])
    cui_terminal_printf(&term, "%s: command not found\n", result.command);
}

static void scene_file_picker(Ui ui) {
  static bool open = true;
  if (ui.button("Open...", { .icon = CUI_ICON_FOLDER_OPEN })) open = true;
  ui.text(chosen.empty() ? "No file chosen." : %"Chose $(chosen.text())", {});
  ui.file_picker("open", open, chosen,
                 { .title = "Open a source file", .start = examples_dir,
                   .filter = "*.x", .filter_label = "x2c sources" });
}

static void scene_markdown(Ui ui) {
  static String notes =
    "## Release notes\n"
    "\n"
    "The gallery now draws **every** component, and `--shots` writes "
    "each one to a PNG. See [the components](docs/components.md).\n"
    "\n"
    "- [x] Layout and text\n"
    "- [x] Files, code, nodes, and docking\n"
    "- [ ] Charts\n"
    "\n"
    "> Scenes keep their state in `static` variables.\n"
    "\n"
    "| Family | Scenes |\n"
    "|:-------|-------:|\n"
    "| Layout | 11 |\n"
    "| Tools | 17 |\n";
  ui.markdown("notes", notes, { .width = CUI_PX(560) });
}

static void scene_code_editor(Ui ui) {
  cui_code_editor_result result = ui.code_editor(
    "editor", source, { .lang = "c", .height = 300,
                        .placeholder = "Write some C" });
  $cui.row(ui, { .gap = 16, .align = CUI_ALIGN_CENTER }) {
    cui_textf(ui, "Ln %d, Col %d", result.line, result.column);
    cui_textf(ui, "%d lines", result.line_count);
    ui.text("Spaces: 4", { .size = 12.5f, .color = CUI_COLOR_TEXT_MUTED });
  }
}

static void scene_diff_view(Ui ui) {
  static int mode = 0, change = 0;
  static String before =
    "int load(config *c, const char *p) {\n"
    "    FILE *f = fopen(p, \"r\");\n"
    "    char buf[256];\n"
    "    int count = 0;\n"
    "    while (fgets(buf, 256, f))\n"
    "        count += parse(c, buf);\n"
    "    fclose(f);\n"
    "    return count;\n"
    "}\n";
  static String after =
    "int load(config *c, const char *p) {\n"
    "    FILE *f = fopen(p, \"r\");\n"
    "    if (!f) return -1;\n"
    "    char buf[256];\n"
    "    int loaded = 0;\n"
    "    while (fgets(buf, 256, f))\n"
    "        loaded += parse(c, buf);\n"
    "    fclose(f);\n"
    "    return loaded;\n"
    "}\n";
  ui.segmented("mode", %("Split" "Inline"), mode, { .size = CUI_SIZE_SM });
  // The options take the selected change as an `int *`.
  cui_diff_result result = ui.diff_view(
    "diff", before, after,
    { .mode = mode ? CUI_DIFF_INLINE : CUI_DIFF_SPLIT, .current = &change,
      .language = "c", .old_title = "config.c (main)",
      .new_title = "config.c", .split_min_width = 520 });
  cui_textf(ui, "Change %d of %d", result.current + 1, result.changes);
}

// A small material graph; pin ids are unique across the editor.
enum { PIN_UV = 1, PIN_TEX_VEC, PIN_TEX_COLOR, PIN_MIX_A, PIN_MIX_B,
       PIN_MIX_FAC, PIN_MIX_OUT, PIN_ROUGH, PIN_OUT_BASE, PIN_OUT_ROUGH };
enum { TYPE_COLOR = 1, TYPE_FLOAT, TYPE_VECTOR };

static void scene_node_editor(Ui ui) {
  static cui_node_view view;
  static float x[5] = { 8, 140, 320, 500, 140 };
  static float y[5] = { 30, 20, 40, 200, 230 };
  static float factor = 0.35f, roughness = 0.62f;
  if (!ui.node_editor_begin("material", view, { .height = CUI_FILL }))
    return;
  ui.node_begin(0, x[0], y[0], "UV", { .width = 110 });
  ui.node_output(PIN_UV, "UV", { .type = TYPE_VECTOR });
  ui.node_end();
  ui.node_begin(1, x[1], y[1], "Brick texture", { .width = 160 });
  ui.node_input(PIN_TEX_VEC, "Vector", { .type = TYPE_VECTOR });
  ui.node_output(PIN_TEX_COLOR, "Color", { .type = TYPE_COLOR });
  ui.node_end();
  ui.node_begin(2, x[2], y[2], "Mix", { .width = 160 });
  ui.node_input(PIN_MIX_A, "Color A", { .type = TYPE_COLOR });
  ui.node_input(PIN_MIX_B, "Color B", { .type = TYPE_COLOR });
  // An input without a link shows a control for its value.
  if (!ui.node_input(PIN_MIX_FAC, "Factor", { .type = TYPE_FLOAT }))
    $cui.node_content(ui) ui.slider("##factor", factor, 0, 1, {});
  ui.node_output(PIN_MIX_OUT, "Color", { .type = TYPE_COLOR });
  ui.node_end();
  ui.node_begin(3, x[3], y[3], "Material output", { .width = 150 });
  ui.node_input(PIN_OUT_BASE, "Base color", { .type = TYPE_COLOR });
  ui.node_input(PIN_OUT_ROUGH, "Roughness", { .type = TYPE_FLOAT });
  ui.node_end();
  ui.node_begin(4, x[4], y[4], "Roughness", { .width = 160 });
  $cui.node_content(ui)
    ui.slider("Value", roughness, 0, 1,
              { .show_value = true, .format = "%.2f" });
  ui.node_output(PIN_ROUGH, "Value", { .type = TYPE_FLOAT });
  ui.node_end();
  ui.node_link(1, PIN_UV, PIN_TEX_VEC);
  ui.node_link(2, PIN_TEX_COLOR, PIN_MIX_A);
  ui.node_link(3, PIN_MIX_OUT, PIN_OUT_BASE);
  ui.node_link(4, PIN_ROUGH, PIN_OUT_ROUGH);
  ui.node_editor_end();
}

static void scene_dockspace(Ui ui) {
  static bool files = true, editor = true, outline = true, shell = true;
  $cui.dockspace(ui, "workspace", {
    .layout = "dock1 h0.26([*Files],v0.6([*main.x,Outline],[*Terminal]))",
    .height = CUI_FILL }) {
    $cui.dock_panel(ui, "Files", files, { .icon = CUI_ICON_FOLDER })
      $cui.column(ui, { .pad = 8, .gap = 6 }) {
        ui.label("examples");
        ui.text("gallery.x", {});
        ui.text("todo.x", {});
        ui.text("gallery/tools.x", {});
      }
    $cui.dock_panel(ui, "main.x", editor, { .icon = CUI_ICON_CODE,
                                             .dirty = true })
      ui.code_editor("dock-editor", source, { .lang = "c", .height = -1 });
    $cui.dock_panel(ui, "Outline", outline, { .icon = CUI_ICON_LIST })
      ui.text("tile_cache_find", {});
    $cui.dock_panel(ui, "Terminal", shell, { .icon = CUI_ICON_TERMINAL })
      ui.terminal("dock-term", term, { .height = -1, .size = 12,
                                       .no_input = true });
  }
}

static void scene_emoji_picker(Ui ui) {
  static int tone = 0;
  $cui.row(ui, { .gap = 24, .align = CUI_ALIGN_START }) {
    /* The options take the skin tone as an `int *` and the
       recent emoji as a `char *recent, size_t recent_cap` pair. CUI draws
       12 new emoji a frame, so a short grid fills in the gallery's three
       frames. */
    String picked = ui.emoji_picker("emoji", { .tone = &tone,
                                               .height = 106 });
    if (picked) status.set(%"$(status.text())$picked");
    $cui.column(ui, { .gap = 10, .width = CUI_FILL }) {
      ui.label("Status");
      ui.input("note", status, { .width = CUI_FILL });
      ui.text("Pick an emoji to add it to the status.",
              { .color = CUI_COLOR_TEXT_MUTED, .size = 12 });
    }
  }
}

static Scene tools_scenes[] = {
  { "path_bar", scene_path_bar },
  { "file_browser", scene_file_browser },
  { "terminal", scene_terminal },
  { "file_picker", scene_file_picker },
  { "markdown", scene_markdown },
  { "code_editor", scene_code_editor },
  { "diff_view", scene_diff_view },
  { "node_editor_begin", scene_node_editor },
  { "node_begin", scene_node_editor },
  { "node_input", scene_node_editor },
  { "node_output", scene_node_editor },
  { "node_content", scene_node_editor },
  { "dockspace_begin", scene_dockspace },
  { "dockspace", scene_dockspace },
  { "dock_panel_begin", scene_dockspace },
  { "dock_panel", scene_dockspace },
  { "emoji_picker", scene_emoji_picker },
};

Family tools_family(void) {
  prepare();
  return (Family){ "Files, code, nodes, and docking", tools_scenes,
                   sizeof tools_scenes / sizeof *tools_scenes };
}
