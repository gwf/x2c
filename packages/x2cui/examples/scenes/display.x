#pragma once

/*  display.x -- scenes for data display, lists, agent interfaces,
    text effects, and motion
*/

#include "scene.x"

static TextField topics, draft;

// The text fields live for the whole program, so they are made once.
static void prepare(void) {
  topics = TextField.new(128);
  topics.set("design, c99, native");
  draft = TextField.new(256);
  draft.set("Summarize the report and compare it with last quarter.");
}

static void scene_empty_state(Ui ui) {
  $cui.card(ui, { .width = CUI_PX(480), .pad = 0 }) {
    if (ui.empty_state("No projects yet", {
          .icon = CUI_ICON_FOLDER_OPEN, .action = "New project",
          .description = "A project holds your screens, their builds and "
                         "who can see them." }))
      ui.toast("Project created", { .tone = CUI_TONE_SUCCESS });
  }
}

static void scene_metric(Ui ui) {
  // cui_metric_opts takes the sparkline as a
  // `const float *spark, int spark_count` pair.
  static const float installs[] = { 3, 5, 4, 7, 6, 9, 11 };
  static const float frame_time[] = { 9, 7, 8, 6, 5, 6, 4, 4, 3 };
  $cui.row(ui, { .gap = 16, .width = CUI_FILL }) {
    ui.metric("Weekly installs", "3,912", {
      .icon = CUI_ICON_DOWNLOAD, .delta = 8.1f,
      .delta_label = "+8.1% vs last week", .spark = installs,
      .spark_count = 7, .width = CUI_GROW(1) });
    ui.metric("Frame time", "0.4 ms", {
      .icon = CUI_ICON_ZAP, .delta = -18.0f, .delta_label = "-18% vs v0.9",
      .lower_is_better = true, .spark = frame_time, .spark_count = 9,
      .width = CUI_GROW(1) });
  }
}

static void scene_accordion(Ui ui) {
  static bool first = true, second = false, third = false;
  $cui.card(ui, { .width = CUI_PX(520), .pad_y = 4, .gap = 0 }) {
    $cui.accordion(ui, "Is it really dependency free?", first)
      ui.secondary("Yes. The core is plain C99, and fonts and icons are "
                   "embedded.");
    $cui.accordion(ui, "Can I use my own renderer?", second)
      ui.secondary("CUI outputs vertices and draw commands for any GPU API.");
    $cui.accordion(ui, "Does it respect reduced motion?", third)
      ui.secondary("Every animation keeps its final state and feedback.");
  }
}

// A file in the tree; a leaf never opens, so it has no children to end.
static void tree_file(Ui ui, String name, bool selected) {
  ui.tree_begin(name, NULL, { .leaf = true, .selected = selected });
}

static void scene_tree(Ui ui) {
  static bool src = true, widgets = true, assets = false;
  $cui.card(ui, { .width = CUI_PX(280), .pad = 10, .gap = 1 }) {
    $cui.tree(ui, "src", src, {}) {
      $cui.tree(ui, "widgets", widgets, {}) {
        tree_file(ui, "button.c", false);
        tree_file(ui, "slider.c", true);
      }
      $cui.tree(ui, "assets", assets, {}) tree_file(ui, "logo.png", false);
      tree_file(ui, "main.c", false);
    }
  }
}

static void scene_list_item(Ui ui) {
  static int chosen = 1;
  static const char *titles[] = { "Design review", "Release 1.0",
                                  "Planning" };
  static const char *people[] = { "Jonas Berg", "Priya Nair",
                                  "Tomas Rivera" };
  static const char *times[] = { "Tomorrow at 10:00", "Ship it",
                                 "Q1 roadmap" };
  static const char *lengths[] = { "45m", "2h", "1h" };
  $cui.card(ui, { .width = CUI_PX(360), .pad = 8, .gap = 2 }) {
    for (int i = 0; i < 3; i++) {
      if (ui.list_item(titles[i], { .avatar = people[i],
                                    .subtitle = times[i],
                                    .trailing = lengths[i],
                                    .selected = i == chosen }))
        chosen = i;
    }
  }
}

static void scene_virtual_list(Ui ui) {
  int first = 0, last = 0;
  ui.text("Ten thousand rows. Only the visible ones are built.",
          { .color = CUI_COLOR_TEXT_MUTED });
  $cui.card(ui, { .width = CUI_PX(420), .pad = 6 })
  $cui.virtual_list(ui, "invoices", 10000, 36, CUI_PX(288), first, last) {
    for (int i = first; i < last; i++) {
      $cui.row(ui, { .height = CUI_PX(36), .pad_x = 12, .gap = 12,
                     .align = CUI_ALIGN_CENTER }) {
        ui.icon(CUI_ICON_FILE_TEXT, 16, CUI_COLOR_TEXT_MUTED);
        ui.text(%"Invoice 2026-$(20000 - i)",
                { .nowrap = true, .tabular = true, .width = CUI_FILL });
        ui.text(i % 5 == 0 ? "Due" : "Paid",
                { .size = 12, .color = CUI_COLOR_TEXT_MUTED });
      }
    }
  }
}

// An evening sky over two hills, generated into RGBA pixels.
static void paint_landscape(unsigned char *pixels, int width, int height) {
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      unsigned char *p = pixels + (y * width + x) * 4;
      int far = height * 3 / 5 + (x - width / 3) * (x - width / 3) / 400;
      int near = height * 3 / 4 + (x - width) * (x - width) / 900;
      int sky = y * 255 / height;
      p[0] = (unsigned char) (y > near ? 40 : y > far ? 70 : 250 - sky / 3);
      p[1] = (unsigned char) (y > near ? 90 : y > far ? 120 : 140 + sky / 3);
      p[2] = (unsigned char) (y > near ? 60 : y > far ? 110 : 90 + sky / 2);
      p[3] = 255;
    }
  }
}

static void scene_image(Ui ui) {
  static cui_texture landscape;
  static unsigned char pixels[320 * 200 * 4];
  if (!landscape) {
    paint_landscape(pixels, 320, 200);
    landscape = ui.image_create(320, 200, pixels);
  }
  ui.image(landscape, { .width = CUI_PX(320), .height = CUI_PX(200),
                        .radius = 12 });
  ui.text("Evening over the hills, 320 by 200 pixels.",
          { .size = 12, .color = CUI_COLOR_TEXT_MUTED });
}

static void scene_tag_input(Ui ui) {
  $cui.column(ui, { .width = CUI_PX(420) })
    ui.tag_input("topics", topics, { .label = "Topics",
                                     .placeholder = "Add a topic" });
}

static void scene_button_group(Ui ui) {
  $cui.button_group(ui) {
    ui.button("Bold", { .icon = CUI_ICON_BOLD });
    ui.button("Italic", { .icon = CUI_ICON_ITALIC });
    ui.button("Underline", { .icon = CUI_ICON_UNDERLINE });
  }
}

static void scene_hold_button(Ui ui) {
  ui.text("Hold the button until it fills to delete the project.",
          { .color = CUI_COLOR_TEXT_MUTED });
  if (ui.hold_button("Hold to delete", { .icon = CUI_ICON_TRASH_2 }))
    ui.toast("Project deleted", { .tone = CUI_TONE_DANGER });
}

static void scene_reorder_item(Ui ui) {
  static int order[] = { 0, 1, 2, 3, 4 };
  static const char *tasks[] = {
    "Write the release notes", "Record the demo video",
    "Update the screenshots", "Tag version 1.0", "Post the announcement" };
  static const char *labels[] = { "Docs", "Video", "Docs", "Release",
                                  "Blog" };
  static const cui_tone tones[] = { CUI_TONE_INFO, CUI_TONE_NEUTRAL,
                                    CUI_TONE_INFO, CUI_TONE_WARNING,
                                    CUI_TONE_TEAL };
  ui.text("Drag a row. The others make room as you go.",
          { .color = CUI_COLOR_TEXT_MUTED });
  $cui.column(ui, { .width = CUI_PX(440) }) {
    // cui_reorder_begin(cui_ctx *, const char *id,
    // int *order, int count) has no method for its array and count.
    cui_reorder_begin(ui, "tasks", order, 5);
    for (int i = 0; i < 5; i++) {
      int task = order[i];
      $cui.reorder_item(ui, i) {
        ui.text(tasks[task], { .nowrap = true, .width = CUI_FILL });
        ui.badge(labels[task], { .tone = tones[task] });
      }
    }
    if (ui.reorder_end()) ui.toast("Order saved", {});
  }
}

static void scene_timeline_item(Ui ui) {
  $cui.column(ui, { .width = CUI_PX(380), .gap = 0 }) {
    ui.timeline_item("Deployed to production", {
      .time = "2m ago", .description = "Release 1.0.3 is live in all "
                                       "regions.",
      .icon = CUI_ICON_ROCKET, .tone = CUI_TONE_SUCCESS });
    ui.timeline_item("Review requested", {
      .time = "1h ago",
      .description = "Jonas asked you to review the theming changes.",
      .icon = CUI_ICON_MESSAGE_SQUARE, .tone = CUI_TONE_INFO });
    ui.timeline_item("Build failed", {
      .time = "3h ago", .icon = CUI_ICON_CIRCLE_ALERT,
      .tone = CUI_TONE_DANGER, .last = true });
  }
}

static void scene_kanban_column_begin(Ui ui) {
  static const char *columns[] = { "Backlog", "In progress", "Done" };
  static const char *cards[3][2] = {
    { "Audit the color tokens", "Virtualize the feed" },
    { "Keyboard nav in date ranges", NULL },
    { "Spring presets", NULL } };
  static const char *owners[3][2] = {
    { "Maya Okafor", "Jonas Berg" }, { "Priya Nair", NULL },
    { "Rosa Delgado", NULL } };
  static const int counts[] = { 2, 1, 1 };
  cui_kanban_move move;
  ui.kanban_begin("board");
  for (int c = 0; c < 3; c++) {
    ui.kanban_column_begin(columns[c], counts[c], {
      .dot = CUI_COLOR_SERIES(c), .limit = c == 1 ? 3 : 0, .width = 200 });
    for (int k = 0; k < counts[c]; k++) {
      ui.kanban_card_begin(c * 10 + k);
      ui.text(cards[c][k], { .font = CUI_FONT_MEDIUM, .size = 13.5f });
      $cui.row(ui, { .gap = 8, .align = CUI_ALIGN_CENTER }) {
        ui.avatar(owners[c][k], { .size = 22 });
        ui.text(owners[c][k], { .size = 12, .color = CUI_COLOR_TEXT_MUTED });
      }
      ui.kanban_card_end();
    }
    ui.kanban_column_end();
  }
  if (ui.kanban_end(move)) ui.toast("Card moved", {});
}

static void scene_reasoning(Ui ui) {
  $cui.column(ui, { .width = CUI_PX(520), .gap = 10 })
  $cui.reasoning(ui, "think", { .thinking = true, .seconds = 6 }) {
    ui.text("The question is about perceived speed: how little work a "
            "frame does, and how fast input reaches the screen.",
            { .size = 13.5f, .color = CUI_COLOR_TEXT_SECONDARY });
    ui.text("Look for sources on retained and immediate mode, text "
            "rendering and motion.",
            { .size = 13.5f, .color = CUI_COLOR_TEXT_SECONDARY });
  }
}

static void scene_tool_call(Ui ui) {
  $cui.column(ui, { .width = CUI_PX(560), .gap = 10 }) {
    ui.tool_call("search", "web_search", {
      .icon = CUI_ICON_GLOBE, .detail = "immediate mode gui performance",
      .status = CUI_TASK_DONE, .seconds = 1.4f,
      .input = "{\"query\": \"immediate mode gui performance\"}",
      .output = "{\"results\": 5, \"took_ms\": 1380}" });
    ui.tool_call("read", "read_file", {
      .icon = CUI_ICON_FILE_TEXT, .detail = "quarterly-report.pdf",
      .status = CUI_TASK_RUNNING, .seconds = 3.2f });
    ui.tool_call("run", "run_tests", {
      .icon = CUI_ICON_SQUARE_TERMINAL, .detail = "ctest --output-on-failure",
      .status = CUI_TASK_FAILED, .seconds = 12.0f });
  }
}

static void scene_agent_status(Ui ui) {
  ui.agent_status("Reading quarterly-report.pdf",
                  { .status = CUI_TASK_RUNNING, .seconds = 14 });
  ui.agent_status("Searched 12 sites", { .status = CUI_TASK_DONE,
                                         .seconds = 9 });
  ui.agent_status("Could not reach the API", { .status = CUI_TASK_FAILED });
}

static void scene_context_meter(Ui ui) {
  // cui_context_opts takes the breakdown as a
  // `const cui_viz_item *parts, int part_count` pair.
  static const cui_viz_item parts[] = {
    { "System", 3200 }, { "Files", 41800 }, { "Messages", 68400 } };
  $cui.row(ui, { .gap = 10, .align = CUI_ALIGN_CENTER }) {
    ui.context_meter("context", 113400, 200000,
                     { .parts = parts, .part_count = 3 });
    ui.text("113k of 200k tokens used. Hover the ring for a breakdown.",
            { .color = CUI_COLOR_TEXT_SECONDARY });
  }
}

static void scene_response_actions(Ui ui) {
  // cui_response_actions_opts takes the vote as `int *vote`,
  // an option field that needs `&`.
  static int vote = 1;
  $cui.column(ui, { .width = CUI_PX(520), .gap = 8 }) {
    ui.text("They do very little work per frame: the interface is rebuilt "
            "from your data, laid out once and drawn in a handful of "
            "batches.", {});
    int action = ui.response_actions("actions", {
      .copy_text = "They do very little work per frame.", .vote = &vote });
    if (action & CUI_RESPONSE_COPY) ui.toast("Copied", {});
  }
}

static void scene_chat_composer(Ui ui) {
  // cui_composer_opts takes `const char *const *attachments,
  // int attachment_count`, `const cui_model *models, int model_count`, and
  // the option field `int *model`, which needs `&`.
  static const char *files[] = { "quarterly-report.pdf", "metrics.csv" };
  static const cui_model models[] = {
    { "Atlas", "Longer answers, reads files and code", "New",
      CUI_ICON_LAYERS },
    { "Atlas Fast", "Short answers in about a second", NULL, CUI_ICON_ZAP },
    { "Atlas Mini", "Runs on your own machine", NULL, CUI_ICON_BOX } };
  static int model = 0;
  int events = ui.chat_composer("composer", draft, {
    .placeholder = "Ask a follow up", .attachments = files,
    .attachment_count = 2, .models = models, .model_count = 3,
    .model = &model, .width = CUI_FILL });
  if (events & CUI_COMPOSER_SEND) draft.set("");
}

static void scene_voice_orb(Ui ui) {
  static const char *names[] = { "Idle", "Listening", "Thinking",
                                 "Speaking" };
  static const float levels[] = { 0.2f, 0.7f, 0.2f, 0.5f };
  $cui.row(ui, { .gap = 18, .align = CUI_ALIGN_CENTER }) {
    for (int k = 0; k < 4; k++) {
      $cui.id_index(ui, k) $cui.column(ui, { .align = CUI_ALIGN_CENTER,
                                             .gap = 6 }) {
        ui.voice_orb("orb", (cui_voice_state) k, levels[k], { .size = 130 });
        ui.text(names[k], { .size = 13, .color = CUI_COLOR_TEXT_SECONDARY });
      }
    }
  }
}

static void scene_shimmer_text(Ui ui) {
  $cui.row(ui, { .gap = 10, .align = CUI_ALIGN_CENTER }) {
    ui.loader({ .style = CUI_LOADER_DOTS, .size = 22 });
    ui.shimmer_text("Thinking about your question...", { .size = 15 });
  }
}

static void scene_typewriter(Ui ui) {
  $cui.column(ui, { .width = CUI_PX(520) })
    ui.typewriter("answer", "CUI draws a full frame in a fraction of a "
                  "millisecond, so text can stream in as fast as it "
                  "arrives.", { .size = 15, .caret = true, .speed = 400 });
}

static void scene_text_reveal(Ui ui) {
  // A negative delay starts the reveal part way in, so the first words
  // are already in place on the first frames.
  ui.text_reveal("build", "The release build finished in 3 minutes "
                 "42 seconds.", { .font = CUI_FONT_DISPLAY, .size = 24,
                                  .width = CUI_PX(600), .delay = -0.4f });
}

static void scene_word_rotate(Ui ui) {
  $cui.row(ui, { .gap = 8, .align = CUI_ALIGN_CENTER }) {
    ui.text("Deploying to", { .font = CUI_FONT_DISPLAY, .size = 26 });
    ui.word_rotate("regions", %("staging." "eu-west." "all regions."), 2.2f,
                   { .font = CUI_FONT_DISPLAY, .size = 26 });
  }
}

static void scene_number_roll(Ui ui) {
  static int visits = 642;
  ui.text("Visitors this week", { .color = CUI_COLOR_TEXT_MUTED });
  ui.number_roll("visits", %"$(visits / 10).$(visits % 10)k",
                 { .font = CUI_FONT_DISPLAY, .size = 40 });
  $cui.row(ui, { .gap = 8 }) {
    if (ui.button("Add 100", { .icon = CUI_ICON_PLUS })) visits++;
    if (ui.button("Remove 100", { .variant = CUI_BUTTON_GHOST }) &&
        visits > 0)
      visits--;
  }
}

static void scene_gradient_text(Ui ui) {
  ui.gradient_text("Kiln 2.4", { .font = CUI_FONT_DISPLAY, .size = 44,
                                 .from = CUI_RGB(0x6366f1),
                                 .to = CUI_RGB(0xec4899), .animate = true });
  ui.text("The build tool for screens that ship on time.",
          { .color = CUI_COLOR_TEXT_SECONDARY });
}

static void scene_spotlight(Ui ui) {
  static const char *titles[] = { "Software", "OpenGL 3.3", "Your own" };
  static const char *blurbs[] = {
    "Plain C into a pixel buffer. No GPU needed.",
    "The default on desktop. Deploying now.",
    "The core emits triangles; bring any GPU API." };
  $cui.row(ui, { .gap = 14, .align = CUI_ALIGN_STRETCH, .width = CUI_FILL }) {
    for (int k = 0; k < 3; k++) {
      $cui.id_index(ui, k)
      $cui.spotlight(ui, "renderer", { .width = CUI_GROW(1),
                                       .beam = k == 1 }) {
        ui.text(titles[k], { .font = CUI_FONT_MEDIUM, .size = 15 });
        ui.text(blurbs[k], { .size = 13, .color = CUI_COLOR_TEXT_SECONDARY });
      }
    }
  }
}

static void scene_loader(Ui ui) {
  static const char *names[] = { "Dots", "Bars", "Pulse", "Orbit", "Grid" };
  $cui.row(ui, { .gap = 36, .align = CUI_ALIGN_CENTER }) {
    for (int k = 0; k < 5; k++) {
      $cui.column(ui, { .gap = 10, .align = CUI_ALIGN_CENTER }) {
        ui.loader({ .style = (cui_loader_style) k, .size = 30 });
        ui.text(names[k], { .size = 12, .color = CUI_COLOR_TEXT_MUTED });
      }
    }
  }
}

static void scene_dock(Ui ui) {
  $cui.column(ui, { .width = CUI_FILL, .height = CUI_FILL,
                    .justify = CUI_JUSTIFY_END, .align = CUI_ALIGN_CENTER })
  $cui.dock(ui, "dock", {}) {
    if (ui.dock_item(CUI_ICON_FOLDER, "Files",
                     { .color = CUI_RGB(0x3b82f6), .running = true }))
      ui.toast("Files", {});
    ui.dock_item(CUI_ICON_MAIL, "Mail", { .color = CUI_RGB(0x0ea5e9),
                                          .badge = 3, .running = true });
    ui.dock_item(CUI_ICON_CALENDAR, "Calendar",
                 { .color = CUI_RGB(0xef4444) });
    ui.dock_item(CUI_ICON_MUSIC, "Music", { .color = CUI_RGB(0xec4899),
                                            .running = true });
    ui.dock_item(CUI_ICON_SQUARE_TERMINAL, "Terminal",
                 { .color = CUI_RGB(0x27272a) });
    ui.dock_item(CUI_ICON_PALETTE, "Design", { .color = CUI_RGB(0x8b5cf6) });
    ui.dock_separator();
    ui.dock_item(CUI_ICON_SETTINGS, "Settings", {});
    ui.dock_item(CUI_ICON_TRASH_2, "Trash", {});
  }
}

static Scene display_scenes[] = {
  { "empty_state", scene_empty_state },
  { "metric", scene_metric },
  { "accordion", scene_accordion },
  { "tree", scene_tree },
  { "list_item", scene_list_item },
  { "virtual_list", scene_virtual_list },
  { "image", scene_image },
  { "tag_input", scene_tag_input },
  { "button_group", scene_button_group },
  { "hold_button", scene_hold_button },
  { "reorder_item", scene_reorder_item },
  { "timeline_item", scene_timeline_item },
  { "kanban_column_begin", scene_kanban_column_begin },
  { "reasoning", scene_reasoning },
  { "tool_call", scene_tool_call },
  { "agent_status", scene_agent_status },
  { "context_meter", scene_context_meter },
  { "response_actions", scene_response_actions },
  { "chat_composer", scene_chat_composer },
  { "voice_orb", scene_voice_orb },
  { "shimmer_text", scene_shimmer_text },
  { "typewriter", scene_typewriter },
  { "text_reveal", scene_text_reveal },
  { "word_rotate", scene_word_rotate },
  { "number_roll", scene_number_roll },
  { "gradient_text", scene_gradient_text },
  { "spotlight", scene_spotlight },
  { "loader", scene_loader },
  { "dock", scene_dock },
};

Family display_family(void) {
  prepare();
  return (Family){ "Data display, lists, and motion", display_scenes,
                   sizeof display_scenes / sizeof *display_scenes };
}
