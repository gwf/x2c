/*  live.x -- a window drawn from a List that a Lisp session holds

    The interface is the value of the Lisp global `ui`. A `View` draws it
    on every frame, so a form typed in the terminal changes the window
    while it runs:

      (def ui (ui-replace ui 'title '(heading ((id title)) "Renamed" 2)))
      (def clicks 40)

    Usage:
      live                    open the window and read forms from the terminal
      live --shot IMAGE.png   draw off screen, click twice, and write a PNG
*/
import "x2cui" with App, Offscreen, Ui, View, ViewLisp;

#include <poll.h>
#include <stdio.h>
#include <string.h>

static String program = %"
  (def clicks 0)
  (def bump (lambda () (def clicks (+ clicks 1))))
  (def ui
    '(column ((pad 24) (gap 12))
       (heading ((id title)) \"A tiny counter\" 2)
       (button ((variant primary) (on-click bump)) \"Add one\")
       (text () (eval (ui-text \"Clicked \" clicks \" times.\")))))";

static View start(Lisp lisp) {
  ViewLisp.install(lisp);
  lisp.eval_string(program);
  return View.new(lisp, "ui");
}

// Evaluates each line the terminal has ready, and prints its value.
static void read_forms(Lisp lisp) {
  struct pollfd input = { .fd = 0, .events = POLLIN };
  char line[4096];
  while (poll(&input, 1, 0) > 0 && fgets(line, sizeof line, stdin)) {
    try puts(lisp.eval_string(line).repr());
    catch %(?cause *detail): printf("%s %s\n", cause.repr(), detail.repr());
  }
}

static int shot(String image) {
  Lisp lisp = auto Lisp.new();
  View view = start(lisp);
  Offscreen screen = auto Offscreen.open(360, 240);
  Ui ui = screen.ui();
  ui.input_mouse_move(60, 96);
  // Each click is a press and a release, with frames to settle between.
  for (int frame = 0; frame < 10; frame++) {
    if (frame % 4 == 2) ui.input_mouse_button(left, true);
    if (frame % 4 == 3) ui.input_mouse_button(left, false);
    screen.begin();
    view.draw(ui);
    screen.end();
  }
  screen.write_png(image);
  puts(lisp.eval_string("(ui-text \"Clicked \" clicks \" times.\")").string());
  return 0;
}

int main(int argc, char **argv) {
  if (argc == 3 && !strcmp(argv[1], "--shot")) return shot(argv[2]);
  Lisp lisp = auto Lisp.new();
  View view = start(lisp);
  App app = auto App.open(title: "Live", width: 360, height: 240);
  while (app.frame()) {
    Ui ui = app.ui();
    read_forms(lisp);
    view.draw(ui);
    // The terminal is read again within a tenth of a second.
    ui.request_wakeup(0.1f);
  }
  return 0;
}
