#pragma once

/*  ai.x -- the gallery's AI page */

#include "state.x"
#include <math.h>

static TextField draft;

static void prepare(void) {
  draft = TextField.new(512);
}

void page_ai(Ui ui, Gallery g) {
  static bool ready = false;
  if (!ready) {
    prepare();
    ready = true;
  }
  static int model = 0, vote = 0, orb_state = 1, removed = -1;
  static bool busy = false;
  static double started = -1;
  static const char *files[] = { "quarterly-report.pdf", "metrics.csv" };
  static int file_count = 2;
  static const cui_model models[] = {
    { "Atlas", "Longer answers, reads files and code", "New",
      CUI_ICON_LAYERS },
    { "Atlas Fast", "Short answers in about a second", NULL, CUI_ICON_ZAP },
    { "Atlas Mini", "Runs on your own machine", NULL, CUI_ICON_BOX },
  };
  static const cui_source sources[] = {
    { "Immediate mode GUIs and why they keep coming back",
      "https://fieldnotes.dev/immediate-mode",
      "A look at retained and immediate mode toolkits and the trade offs "
      "between them." },
    { "Notes on subpixel text positioning",
      "https://glyphlab.io/notes/subpixel",
      "Shaping, hinting and subpixel positioning explained with examples." },
    { "Spring physics for interface motion",
      "https://motionbook.dev/springs",
      "Why spring physics feel more natural than cubic beziers for "
      "interface motion." },
  };
  double now = ui.time();
  if (busy && started < 0) started = now;
  if (!busy) started = -1;
  float elapsed = busy ? (float) (now - started) : 0;
  if (busy && elapsed > 9) busy = false;
  $cui.row(ui, { .gap = 28, .align = CUI_ALIGN_START, .width = CUI_FILL }) {
    $cui.column(ui, { .width = CUI_GROW(1.6f), .gap = 14 }) {
      section(ui, "Conversation", "Reasoning, tool calls, an answer with "
                                  "sources, and the composer.");
      ui.chat_message("Why do immediate mode toolkits feel so fast? Cite a "
                      "few sources.", mine: true);
      $cui.reasoning(ui, "think", { .thinking = busy,
                                    .seconds = busy ? elapsed : 8 }) {
        ui.text("The question is about perceived speed. Two parts: how "
                "little work a frame does, and how quickly input shows up "
                "on screen.",
                size: 13.5f, color: CUI_COLOR_TEXT_SECONDARY);
        ui.text("Look for sources on retained versus immediate mode, text "
                "rendering cost and motion.",
                size: 13.5f, color: CUI_COLOR_TEXT_SECONDARY);
      }
      ui.tool_call("search", "web_search",
        icon: CUI_ICON_GLOBE, detail: "immediate mode gui performance",
        status: CUI_TASK_DONE, seconds: 1.4f,
        input: "{\"query\": \"immediate mode gui performance\", "
                 "\"limit\": 5}",
        output: "{\"results\": [{\"title\": \"Immediate mode GUIs\", "
                  "\"url\": \"https://fieldnotes.dev/immediate-mode\"}], "
                  "\"took_ms\": 1380}");
      ui.tool_call("read", "read_file",
        icon: CUI_ICON_FILE_TEXT, detail: "quarterly-report.pdf",
        status: busy ? CUI_TASK_RUNNING : CUI_TASK_DONE,
        seconds: busy ? elapsed : 2.1f);
      if (busy)
        ui.agent_status("Reading quarterly-report.pdf",
          status: CUI_TASK_RUNNING, seconds: elapsed);
      ui.typewriter("answer", "They do very little work per frame: the "
                    "interface is rebuilt from your data, laid out once "
                    "and drawn in a handful of batches, so there is no "
                    "tree of objects to keep in sync. Text is the "
                    "expensive part, which is why glyphs are cached in an "
                    "atlas, and motion feels quick when it is driven by "
                    "springs instead of fixed curves.", size: 15);
      $cui.row(ui, { .gap = 6, .align = CUI_ALIGN_CENTER }) {
        ui.text("Sources", size: 12, color: CUI_COLOR_TEXT_MUTED);
        for (int k = 0; k < $cui.count(sources); k++)
          ui.citation(k + 1, sources[k]);
      }
      ui.source_list("sources", sources, $cui.count(sources));
      $cui.row(ui, { .gap = 8, .align = CUI_ALIGN_CENTER,
                     .width = CUI_FILL }) {
        int actions = ui.response_actions("actions",
          copy_text: "They do very little work per frame.",
          vote: &vote);
        if (actions & CUI_RESPONSE_REGENERATE) busy = true;
        ui.spacer();
        static const cui_viz_item parts[] = {
          { "System", 3200 }, { "Files", 41800 }, { "Messages", 68400 } };
        ui.context_meter("ctx", 113400, 200000,
          parts: parts, part_count: $cui.count(parts));
      }
      int event = ui.chat_composer("composer", draft,
        placeholder: "Ask a follow up", busy: busy,
        attachments: files, attachment_count: file_count,
        removed: &removed, models: models,
        model_count: $cui.count(models), model: &model);
      if (event & CUI_COMPOSER_SEND) {
        draft.set("");
        busy = true;
      }
      if (event & CUI_COMPOSER_STOP) busy = false;
      if ((event & CUI_COMPOSER_REMOVE) && removed >= 0 &&
          removed < file_count) {
        for (int k = removed; k < file_count - 1; k++) files[k] = files[k + 1];
        file_count--;
      }
      if (event & CUI_COMPOSER_ATTACH)
        ui.toast("Attach files",
          description: "Drop files on the window, too.");
    }
    $cui.column(ui, { .width = CUI_GROW(1), .gap = 14 }) {
      section(ui, "Agent plan", "Steps and their status.");
      cui_plan_step steps[] = {
        { "Search for sources", "3 results", CUI_TASK_DONE },
        { "Read the attached report", busy ? "Page 12 of 40" : "40 pages",
          busy ? CUI_TASK_RUNNING : CUI_TASK_DONE },
        { "Compare the numbers with last quarter", NULL,
          busy ? CUI_TASK_PENDING : CUI_TASK_DONE },
        { "Draft the summary", NULL,
          busy ? CUI_TASK_PENDING : CUI_TASK_RUNNING },
        { "Check the citations", NULL, CUI_TASK_PENDING },
      };
      // The page ignores the result, so the method stands in for the macro.
      ui.agent_plan("plan", steps, $cui.count(steps),
        title: "Research plan");
      section(ui, "Voice", "Idle, listening, thinking and speaking.");
      $cui.column(ui, { .align = CUI_ALIGN_CENTER, .gap = 12,
                        .width = CUI_FILL }) {
        float level = 0.35f + 0.35f * sinf((float) now * 5.1f) *
                                      sinf((float) now * 1.7f);
        if (ui.voice_orb("orb", (cui_voice_state) orb_state, level,
                         size: 170))
          orb_state = orb_state == 1 ? 0 : 1;
        ui.segmented("orb-state",
                     %("Idle" "Listening" "Thinking" "Speaking"), orb_state,
                     size: CUI_SIZE_SM);
      }
      section(ui, "Suggestions", "Ways to start.");
      static const cui_prompt_suggestion suggestions[] = {
        { CUI_ICON_CODE, "Explain this code", "Walk through what it does" },
        { CUI_ICON_CHART_BAR, "Analyze a dataset",
          "Find trends and outliers" },
        { CUI_ICON_PENCIL, "Draft an email", "Clear and friendly" },
        { CUI_ICON_BUG, "Debug an error", "Paste the stack trace" },
      };
      int picked = ui.prompt_suggestions(
        "sugg", suggestions, $cui.count(suggestions), columns: 1);
      if (picked >= 0) draft.set(%"$(suggestions[picked].title): ");
    }
  }
}
