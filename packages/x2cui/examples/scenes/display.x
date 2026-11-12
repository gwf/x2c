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
  ui.card (width: 480, pad: 0) {
    if (ui.empty_state("No projects yet",
          icon: folder_open, action: "New project",
          description: "A project holds your screens, their builds and "
                         "who can see them."))
      ui.toast("Project created", tone: success);
  }
}

static void scene_metric(Ui ui) {
  // cui_metric_opts takes the sparkline as a
  // `const float *spark, int spark_count` pair.
  static const float installs[] = { 3, 5, 4, 7, 6, 9, 11 };
  ui.row (gap: 16, width: fill) {
    ui.metric("Weekly installs", "3,912",
      icon: download, delta: 8.1f,
      delta_label: "+8.1% vs last week", spark: installs,
      spark_count: 7, width: grow(1));
    ui.metric("Frame time", "0.4 ms",
      icon: zap, delta: -18.0f, delta_label: "-18% vs v0.9",
      lower_is_better: true, spark: [9, 7, 8, 6, 5, 6, 4, 4, 3], spark_count: 9,
      width: grow(1));
  }
}

static void scene_accordion(Ui ui) {
  static bool first = true, second = false, third = false;
  ui.card (width: 520, pad_y: 4, gap: 0) {
    ui.accordion ("Is it really dependency free?", first)
      ui.secondary("Yes. The core is plain C99, and fonts and icons are "
                   "embedded.");
    ui.accordion ("Can I use my own renderer?", second)
      ui.secondary("CUI outputs vertices and draw commands for any GPU API.");
    ui.accordion ("Does it respect reduced motion?", third)
      ui.secondary("Every animation keeps its final state and feedback.");
  }
}

// A file in the tree; a leaf never opens, so its block is empty.
static void tree_file(Ui ui, String name, bool selected) {
  ui.tree (name, NULL, leaf: true, selected: selected) {}
}

static void scene_tree(Ui ui) {
  static bool src = true, widgets = true, assets = false;
  ui.card (width: 280, pad: 10, gap: 1) {
    ui.tree ("src", src) {
      ui.tree ("widgets", widgets) {
        tree_file(ui, "button.c", false);
        tree_file(ui, "slider.c", true);
      }
      ui.tree ("assets", assets) tree_file(ui, "logo.png", false);
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
  ui.card (width: 360, pad: 8, gap: 2) {
    for (int i = 0; i < 3; i++) {
      if (ui.list_item(titles[i], avatar: people[i],
                                  subtitle: times[i],
                                  trailing: lengths[i],
                                  selected: i == chosen))
        chosen = i;
    }
  }
}

static void scene_virtual_list(Ui ui) {
  int first = 0, last = 0;
  ui.text("Ten thousand rows. Only the visible ones are built.",
          color: text_muted);
  ui.card (width: 420, pad: 6)
  ui.virtual_list ("invoices", 10000, 36, 288, first, last) {
    for (int i = first; i < last; i++) {
      ui.row (height: 36, pad_x: 12, gap: 12,
              align: center) {
        ui.icon(file_text, 16, text_muted);
        ui.text(%"Invoice 2026-$(20000 - i)",
                nowrap: true, tabular: true, width: fill);
        ui.text(i % 5 == 0 ? "Due" : "Paid",
                size: 12, color: text_muted);
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
  ui.image(landscape, width: 320, height: 200,
                      radius: 12);
  ui.text("Evening over the hills, 320 by 200 pixels.",
          size: 12, color: text_muted);
}

static void scene_tag_input(Ui ui) {
  ui.column (width: 420)
    ui.tag_input("topics", topics, label: "Topics",
                                   placeholder: "Add a topic");
}

static void scene_button_group(Ui ui) {
  ui.button_group () {
    ui.button("Bold", icon: bold);
    ui.button("Italic", icon: italic);
    ui.button("Underline", icon: underline);
  }
}

static void scene_hold_button(Ui ui) {
  ui.text("Hold the button until it fills to delete the project.",
          color: text_muted);
  if (ui.hold_button("Hold to delete", icon: trash_2))
    ui.toast("Project deleted", tone: danger);
}

static void scene_reorder_item(Ui ui) {
  static ArrayInt order;
  if (!order) order = [0, 1, 2, 3, 4];
  static const char *tasks[] = {
    "Write the release notes", "Record the demo video",
    "Update the screenshots", "Tag version 1.0", "Post the announcement" };
  static const char *labels[] = { "Docs", "Video", "Docs", "Release",
                                  "Blog" };
  static const cui_tone tones[] = { CUI_TONE_INFO, CUI_TONE_NEUTRAL,
                                    CUI_TONE_INFO, CUI_TONE_WARNING,
                                    CUI_TONE_TEAL };
  ui.text("Drag a row. The others make room as you go.",
          color: text_muted);
  ui.column (width: 440) {
    bool changed;
    ui.reorder (changed, "tasks", order)
    for (int i = 0; i < 5; i++) {
      int task = order[i];
      ui.reorder_item (i) {
        ui.text(tasks[task], nowrap: true, width: fill);
        ui.badge(labels[task], tone: tones[task]);
      }
    }
    if (changed) ui.toast("Order saved");
  }
}

static void scene_timeline_item(Ui ui) {
  ui.column (width: 380, gap: 0) {
    ui.timeline_item("Deployed to production",
      time: "2m ago", description: "Release 1.0.3 is live in all "
                                       "regions.",
      icon: rocket, tone: success);
    ui.timeline_item("Review requested",
      time: "1h ago",
      description: "Jonas asked you to review the theming changes.",
      icon: message_square, tone: info);
    ui.timeline_item("Build failed",
      time: "3h ago", icon: circle_alert,
      tone: danger, last: true);
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
  bool moved, added, clicked;
  cui_kanban_move move;
  ui.kanban (moved, move, "board")
  for (int c = 0; c < 3; c++)
    ui.kanban_column (added, columns[c], counts[c],
                      dot: CUI_COLOR_SERIES(c), limit: c == 1 ? 3 : 0,
                      width: 200)
    for (int k = 0; k < counts[c]; k++)
      ui.kanban_card (clicked, c * 10 + k) {
        ui.text(cards[c][k], font: medium, size: 13.5f);
        ui.row (gap: 8, align: center) {
          ui.avatar(owners[c][k], size: 22);
          ui.text(owners[c][k], size: 12, color: text_muted);
        }
      }
  if (moved) ui.toast("Card moved");
}

static void scene_reasoning(Ui ui) {
  ui.column (width: 520, gap: 10)
  ui.reasoning ("think", thinking: true, seconds: 6) {
    ui.text("The question is about perceived speed: how little work a "
            "frame does, and how fast input reaches the screen.",
            size: 13.5f, color: text_secondary);
    ui.text("Look for sources on retained and immediate mode, text "
            "rendering and motion.",
            size: 13.5f, color: text_secondary);
  }
}

static void scene_tool_call(Ui ui) {
  ui.column (width: 560, gap: 10) {
    ui.tool_call("search", "web_search",
      icon: globe, detail: "immediate mode gui performance",
      status: done, seconds: 1.4f,
      input: "{\"query\": \"immediate mode gui performance\"}",
      output: "{\"results\": 5, \"took_ms\": 1380}");
    ui.tool_call("read", "read_file",
      icon: file_text, detail: "quarterly-report.pdf",
      status: running, seconds: 3.2f);
    ui.tool_call("run", "run_tests",
      icon: square_terminal, detail: "ctest --output-on-failure",
      status: failed, seconds: 12.0f);
  }
}

static void scene_agent_status(Ui ui) {
  ui.agent_status("Reading quarterly-report.pdf",
                  status: running, seconds: 14);
  ui.agent_status("Searched 12 sites", status: done,
                                       seconds: 9);
  ui.agent_status("Could not reach the API", status: failed);
}

static void scene_context_meter(Ui ui) {
  // cui_context_opts takes the breakdown as a
  // `const cui_viz_item *parts, int part_count` pair.
  static const cui_viz_item parts[] = {
    { "System", 3200 }, { "Files", 41800 }, { "Messages", 68400 } };
  ui.row (gap: 10, align: center) {
    ui.context_meter("context", 113400, 200000,
                     parts: parts, part_count: 3);
    ui.text("113k of 200k tokens used. Hover the ring for a breakdown.",
            color: text_secondary);
  }
}

static void scene_response_actions(Ui ui) {
  // cui_response_actions_opts takes the vote as `int *vote`,
  // an option field that needs `&`.
  static int vote = 1;
  ui.column (width: 520, gap: 8) {
    ui.text("They do very little work per frame: the interface is rebuilt "
            "from your data, laid out once and drawn in a handful of "
            "batches.");
    int action = ui.response_actions("actions",
      copy_text: "They do very little work per frame.", vote: &vote);
    if (action & CUI_RESPONSE_COPY) ui.toast("Copied");
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
  int events = ui.chat_composer("composer", draft,
    placeholder: "Ask a follow up", attachments: files,
    attachment_count: 2, models: models, model_count: 3,
    model: &model, width: fill);
  if (events & CUI_COMPOSER_SEND) draft.set("");
}

static void scene_voice_orb(Ui ui) {
  static const char *names[] = { "Idle", "Listening", "Thinking",
                                 "Speaking" };
  static const float levels[] = { 0.2f, 0.7f, 0.2f, 0.5f };
  ui.row (gap: 18, align: center) {
    for (int k = 0; k < 4; k++) {
      ui.id (k) ui.column (align: center,
                                      gap: 6) {
        ui.voice_orb("orb", (cui_voice_state) k, levels[k], size: 130);
        ui.text(names[k], size: 13, color: text_secondary);
      }
    }
  }
}

static void scene_shimmer_text(Ui ui) {
  ui.row (gap: 10, align: center) {
    ui.loader(style: dots, size: 22);
    ui.shimmer_text("Thinking about your question...", size: 15);
  }
}

static void scene_typewriter(Ui ui) {
  ui.column (width: 520)
    ui.typewriter("answer", "CUI draws a full frame in a fraction of a "
                  "millisecond, so text can stream in as fast as it "
                  "arrives.", size: 15, caret: true, speed: 400);
}

static void scene_text_reveal(Ui ui) {
  // A negative delay starts the reveal part way in, so the first words
  // are already in place on the first frames.
  ui.text_reveal("build", "The release build finished in 3 minutes "
                 "42 seconds.", font: display, size: 24,
                                width: 600, delay: -0.4f);
}

static void scene_word_rotate(Ui ui) {
  ui.row (gap: 8, align: center) {
    ui.text("Deploying to", font: display, size: 26);
    ui.word_rotate("regions", %("staging." "eu-west." "all regions."), 2.2f,
                   font: display, size: 26);
  }
}

static void scene_number_roll(Ui ui) {
  static int visits = 642;
  ui.text("Visitors this week", color: text_muted);
  ui.number_roll("visits", %"$(visits / 10).$(visits % 10)k",
                 font: display, size: 40);
  ui.row (gap: 8) {
    if (ui.button("Add 100", icon: plus)) visits++;
    if (ui.button("Remove 100", variant: ghost) &&
        visits > 0)
      visits--;
  }
}

static void scene_gradient_text(Ui ui) {
  ui.gradient_text("Kiln 2.4", font: display, size: 44,
                               from: CUI_RGB(0x6366f1),
                               to: CUI_RGB(0xec4899), animate: true);
  ui.text("The build tool for screens that ship on time.",
          color: text_secondary);
}

static void scene_spotlight(Ui ui) {
  static const char *titles[] = { "Software", "OpenGL 3.3", "Your own" };
  static const char *blurbs[] = {
    "Plain C into a pixel buffer. No GPU needed.",
    "The default on desktop. Deploying now.",
    "The core emits triangles; bring any GPU API." };
  ui.row (gap: 14, align: stretch, width: fill) {
    for (int k = 0; k < 3; k++) {
      ui.id (k)
      ui.spotlight ("renderer", width: grow(1),
                                beam: k == 1) {
        ui.text(titles[k], font: medium, size: 15);
        ui.text(blurbs[k], size: 13, color: text_secondary);
      }
    }
  }
}

static void scene_loader(Ui ui) {
  static const char *names[] = { "Dots", "Bars", "Pulse", "Orbit", "Grid" };
  ui.row (gap: 36, align: center) {
    for (int k = 0; k < 5; k++) {
      ui.column (gap: 10, align: center) {
        ui.loader(style: (cui_loader_style) k, size: 30);
        ui.text(names[k], size: 12, color: text_muted);
      }
    }
  }
}

static void scene_dock(Ui ui) {
  ui.column (width: fill, height: fill,
             justify: end, align: center)
  ui.dock ("dock") {
    if (ui.dock_item(folder, "Files",
                     color: CUI_RGB(0x3b82f6), running: true))
      ui.toast("Files");
    ui.dock_item(mail, "Mail", color: CUI_RGB(0x0ea5e9),
                                        badge: 3, running: true);
    ui.dock_item(calendar, "Calendar",
                 color: CUI_RGB(0xef4444));
    ui.dock_item(music, "Music", color: CUI_RGB(0xec4899),
                                          running: true);
    ui.dock_item(square_terminal, "Terminal",
                 color: CUI_RGB(0x27272a));
    ui.dock_item(palette, "Design", color: CUI_RGB(0x8b5cf6));
    ui.dock_separator();
    ui.dock_item(settings, "Settings");
    ui.dock_item(trash_2, "Trash");
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
