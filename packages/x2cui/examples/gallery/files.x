#pragma once

/*  files.x -- the gallery's Files page */

#include "state.x"

static TextField folder, chosen;

// The shell's output buffer, which CUI fills as text is written.
static char term_text[64 * 1024];
static cui_terminal_line term_lines[1024];
static cui_terminal_buffer term;

/* The local disk, or a few made-up files where there is none (the browser
   build). It is CUI's cui_file_list_fn, so it keeps CUI's C parameters,
   and cui_fs_list takes C buffers. */
static int files_list(void *user, const char *path, cui_file_entry *out,
                      int cap, char *names, size_t names_cap, bool hidden) {
  int n = cui_fs_list(user, path, out, cap, names, names_cap, hidden);
  if (n >= 0 || strcmp(path, ".")) return n;
  List demo = %("assets" "src" "README.md" "notes.txt" "cover.png"
                "report.pdf");
  for (int k = 0; k < demo.len() && k < cap; k++)
    out[k] = cui_file_entry.of(name: demo[k], dir: k < 2,
                               size: (uint64_t) (k * 13100),
                               modified: 1730000000 + k * 86400);
  return demo.len();
}

static void prepare(void) {
  folder = TextField.new(1024);
  folder.set(".");
  chosen = TextField.new(1024);
  // The terminal functions take C buffers and have no methods.
  cui_terminal_init(&term, term_text, sizeof term_text, term_lines, 1024);
  cui_terminal_write(&term, "Type \x1b[1mhelp\x1b[0m for the commands.\n", -1);
}

// Runs one line typed into the shell.
static void run_command(String c) {
  if (c == "help")
    cui_terminal_write(&term,
                       "  \x1b[36mls\x1b[0m      the folder above\n"
                       "  \x1b[36mcolors\x1b[0m  the 16 colors\n"
                       "  \x1b[36mbuild\x1b[0m   a progress bar\n"
                       "  \x1b[36mecho\x1b[0m    prints its words\n"
                       "  \x1b[36mclear\x1b[0m   empties the screen\n", -1);
  else if (c == "ls") {
    static cui_file_entry entries[256];
    static char names[16384];
    int n = files_list(NULL, folder.text(), entries, 256, names,
                       sizeof names, false);
    for (int k = 0; k < n; k++)
      term.printf(entries[k].dir ? "\x1b[1;34m%s/\x1b[0m\n"
                                                : "%s\n", entries[k].name);
    if (n < 0)
      cui_terminal_write(&term, "\x1b[31mls: cannot read this folder"
                         "\x1b[0m\n", -1);
  }
  else if (c == "colors") {
    for (int k = 0; k < 16; k++)
      term.printf("\x1b[%dm\xe2\x96\x88\xe2\x96\x88\x1b[0m%s",
                          k < 8 ? 30 + k : 82 + k,
                          k == 7 || k == 15 ? "\n" : " ");
  }
  else if (c == "build") {
    String full = "\xe2\x96\x88", empty = "\xe2\x96\x91";
    for (int k = 0; k <= 20; k++) {
      String bar = %"$(full.repeat(k))$(empty.repeat(20 - k))";
      term.printf("\r\x1b[32m%s\x1b[0m %3d%%", bar, k * 5);
    }
    cui_terminal_write(&term, "\n\x1b[32mdone\x1b[0m\n", -1);
  }
  else if (c == "echo" || c.startswith("echo "))
    term.printf("%s\n",
                        c == "echo" ? "" : c.remove_prefix("echo "));
  else if (c == "clear") cui_terminal_clear(&term);
  else if (c[0])
    term.printf("\x1b[31m%s: command not found\x1b[0m\n", c);
}

void page_files(Ui ui, Gallery g) {
  static bool ready = false;
  if (!ready) {
    prepare();
    ready = true;
  }
  static bool open_dlg, save_dlg;
  section(ui, "File browser", "Double-click to open; type to jump; "
                              "Backspace goes up.");
  cui_file_browser_result r = ui.file_browser("files", folder,
    list: files_list, height: 380);
  if (r.picked) chosen.set(r.picked);
  ui.row (gap: 8, align: center, wrap: true) {
    if (ui.button("Open\xe2\x80\xa6", icon: folder_open))
      open_dlg = true;
    if (ui.button("Save as\xe2\x80\xa6", icon: download))
      save_dlg = true;
    if (!chosen.empty()) ui.muted(chosen.text());
  }
  ui.file_picker("open", open_dlg, chosen, list: files_list);
  ui.file_picker("save", save_dlg, chosen,
    list: files_list, save: true, name: "untitled.txt");

  // A small shell over the same folder.
  section(ui, "Terminal", "Colors, \\r progress, history on Up and Down, "
                          "Ctrl+C, Ctrl+L, drag to select.");
  cui_terminal_result tr = ui.terminal("shell", term,
    height: 300, prompt: "> ");
  if (tr.command) run_command(tr.command);
  if (tr.interrupt) ui.toast("Interrupted");
}
