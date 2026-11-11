/*  todo.x -- A to-do list in a window.

    The program keeps its tasks in an ordinary Array and describes the
    whole screen on every frame. It adds a task from a text field, filters
    the list, removes a task, confirms before clearing the finished ones,
    and saves the list to a file after each change.

      todo [FILE]             open a window; FILE defaults to todo.txt
      todo --shot IMAGE.png   draw three sample tasks off screen
*/

import "x2cui" with App, Offscreen, TextField, Ui;

#include "path.x"

class Task { String title; bool done; } *;

void Task.init(Task task, String title, bool done) {
  task.title = title;
  task.done = done;
}

typedef struct Todo {
  Array tasks;
  TextField draft;
  int filter;            // 0 all, 1 open, 2 done
  bool confirm_clear;    // the "Clear finished tasks?" dialog is open
  Path file;             // where the list is saved; NULL keeps it unsaved
} Todo;

// One task a line: "x Buy milk" when done, "- Buy milk" when not.
static void save(Todo &todo) {
  if (!todo.file) return;
  Array lines = [];
  foreach (Task task in todo.tasks)
    lines.push(%"$(task.done ? "x" : "-") $(task.title)\n");
  todo.file.write_text(lines.join(""));
}

static void load(Todo &todo) {
  if (!todo.file || !todo.file.exists()) return;
  foreach (String line in todo.file.read_text().split_lines(0))
    if (line.len() > 2) todo.tasks.push(Task.new(line[2:], line[0] == 'x'));
}

static bool shown(Task task, int filter) =>
  filter == 0 || (filter == 2) == task.done;

static void draw(Ui ui, Todo &todo) {
  bool changed = false;
  int done = 0, visible = 0, removed = -1;
  foreach (Task task in todo.tasks) done += task.done;
  int open = (int) todo.tasks.len() - done;

  $cui.column(ui, { .width = CUI_FILL, .height = CUI_FILL,
                    .align = CUI_ALIGN_CENTER, .bg = CUI_COLOR_BACKGROUND })
  $cui.column(ui, { .width = CUI_FILL, .max_width = 560, .height = CUI_FILL,
                    .pad = 24, .gap = 16 }) {
    $cui.row(ui, { .gap = 12, .align = CUI_ALIGN_END }) {
      ui.heading("To do", 2);
      ui.spacer();
      ui.text(%"$open open, $done done", {});
    }

    // Enter in the field or the button adds the task.
    $cui.row(ui, { .gap = 8 }) {
      int typed = ui.input("new-task", todo.draft,
                           { .placeholder = "Add a task", .width = CUI_FILL });
      bool add = ui.button("Add", { .variant = CUI_BUTTON_PRIMARY,
                                    .icon = CUI_ICON_PLUS,
                                    .disabled = todo.draft.empty() });
      if ((add || typed & CUI_SUBMITTED) && !todo.draft.empty()) {
        todo.tasks.push(Task.new(todo.draft.take(), false));
        changed = true;
      }
    }

    $cui.row(ui, { .gap = 8, .align = CUI_ALIGN_CENTER }) {
      ui.segmented("filter", %("All" "Open" "Done"), todo.filter, {});
      ui.spacer();
      if (ui.button("Clear done", { .variant = CUI_BUTTON_GHOST,
                                    .disabled = done == 0 }))
        todo.confirm_clear = true;
    }

    $cui.scroll(ui, { .id = "tasks", .width = CUI_FILL, .height = CUI_FILL,
                      .gap = 2 }) {
      for (int i = 0; i < (int) todo.tasks.len(); i++) {
        Task task = todo.tasks[i];
        if (!shown(task, todo.filter)) continue;
        visible++;
        // The index keeps two tasks with one title apart.
        $cui.id_index(ui, i)
        $cui.row(ui, { .gap = 8, .align = CUI_ALIGN_CENTER,
                       .width = CUI_FILL }) {
          changed |= ui.checkbox(task.title, task.done, {});
          ui.spacer();
          if (ui.icon_button(CUI_ICON_X, { .tooltip = "Delete",
                                           .variant = CUI_BUTTON_GHOST,
                                           .size = CUI_SIZE_SM }))
            removed = i;
        }
      }
      if (!visible) {
        bool empty = !todo.tasks.len();
        ui.empty_state(empty ? "No tasks yet" : "Nothing here", {
          .icon = CUI_ICON_LIST_CHECKS,
          .description = empty ? "Type one above and press Enter."
                               : "No task matches this filter." });
      }
    }
  }

  // After the loop, so this frame's rows stay in step with the Array.
  if (removed >= 0) {
    todo.tasks.remove(removed);
    changed = true;
  }

  $cui.dialog(ui, "Clear finished tasks?", todo.confirm_clear, {
      .description = "They are removed from the list and from the file.",
      .width = 380 })
  $cui.dialog_footer(ui) {
    if (ui.button("Cancel", {})) todo.confirm_clear = false;
    if (ui.button("Clear", { .variant = CUI_BUTTON_DANGER })) {
      todo.tasks = todo.tasks.list().filter(%!(Task task) => !task.done);
      todo.confirm_clear = false;
      changed = true;
      ui.toast("Finished tasks cleared", {});
    }
  }

  if (changed) save(todo);
}

static int shot(Todo &todo, String image) {
  todo.tasks = [Task.new("Read the tutorial", true),
                Task.new("Wrap the components", false),
                Task.new("Draw the gallery", false)];
  Offscreen screen = auto Offscreen.open(520, 640);
  // The second and third frames settle layout and opening animations.
  for (int frame = 0; frame < 3; frame++) {
    screen.begin();
    draw(screen.ui(), todo);
    screen.end();
  }
  screen.write_png(image);
  printf("%s: %d draw commands\n", image, screen.commands());
  return screen.commands() ? 0 : 1;
}

int main(int argc, char **argv) {
  Todo todo = { .tasks = [], .draft = TextField.new(96) };
  if (argc == 3 && !strcmp(argv[1], "--shot")) return shot(todo, argv[2]);

  todo.file = argc > 1 ? argv[1] : "todo.txt";
  load(todo);
  App app = auto App.open({ .title = "To do", .width = 520, .height = 640,
                            .min_width = 360, .min_height = 420 });
  while (app.frame()) draw(app.ui(), todo);
  return 0;
}
