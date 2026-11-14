/*  counter.x -- a small interface supplied by an imported package */
import "x2cui" with App, Ui;

int main(void) {
  App app = auto App.open(title: "Counter", width: 360, height: 240);
  int clicks = 0;
  while (app.frame()) {
    Ui ui = app.ui();
    ui.column (pad: 24, gap: 12) {
      ui.heading("A tiny counter", 2);
      if (ui.button("Add one", variant: primary))
        clicks++;
      ui.text(%"Clicked $clicks times.");
    }
  }
  return 0;
}
