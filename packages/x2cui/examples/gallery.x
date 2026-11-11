/*  gallery.x -- Every CUI component, drawn from x2c.

    Each scene draws one component the way a program would use it. A scene
    is named for its CUI component: the scene `button` shows `ui.button`,
    and the scene `row` shows `$cui.row`. The scene files under gallery/
    group the scenes into families.

      gallery                      browse the scenes in a window
      gallery --list               print the scene names, one a line
      gallery --shots DIR [SCENE]  draw every scene, or one, to DIR/NAME.png
*/

#include "path.x"
#include "gallery/scene.x"
#include "gallery/layout.x"
#include "gallery/controls.x"
#include "gallery/display.x"
#include "gallery/media.x"
#include "gallery/data.x"
#include "gallery/tools.x"
#include "gallery/chrome.x"

#define FAMILY_LIMIT 16

static Family families[FAMILY_LIMIT];
static int family_total;

static int family_count(void) => family_total;

static void add_family(Family family) { families[family_total++] = family; }

static void add_families(void) {
  add_family(layout_family());
  add_family(controls_family());
  add_family(display_family());
  add_family(media_family());
  add_family(data_family());
  add_family(tools_family());
  add_family(chrome_family());
}

// The page every scene is drawn on.
static void draw_page(Ui ui, Scene *scene) {
  $cui.column(ui, { .width = CUI_FILL, .height = CUI_FILL, .pad = 28,
                    .gap = 16, .bg = CUI_COLOR_BACKGROUND })
    scene.draw(ui);
}

static int list_scenes(void) {
  for (int f = 0; f < family_count(); f++)
    for (int s = 0; s < families[f].count; s++)
      printf("%s\n", families[f].scenes[s].name);
  return 0;
}

/* Draws one scene off screen. The second and third frames settle layout
   and opening animations. Returns its draw command count. */
static int shoot(Scene *scene, Path directory) {
  Offscreen screen = auto Offscreen.open(720, 480);
  for (int frame = 0; frame < 3; frame++) {
    screen.begin();
    draw_page(screen.ui(), scene);
    screen.end();
  }
  screen.write_png(directory.join(%"$(scene.name).png"));
  return screen.commands();
}

static int shoot_scenes(Path directory, String only) {
  directory.make_dirs();
  int drawn = 0, empty = 0;
  for (int f = 0; f < family_count(); f++) {
    for (int s = 0; s < families[f].count; s++) {
      Scene *scene = &families[f].scenes[s];
      if (only && scene.name != only) continue;
      drawn++;
      if (shoot(scene, directory)) continue;
      printf("%s drew nothing\n", scene.name);
      empty++;
    }
  }
  printf("%d scenes drawn to %s, %d empty\n", drawn, directory, empty);
  return drawn && !empty ? 0 : 1;
}

// The window: families and scenes on the left, the chosen scene on the right.
static void draw_browser(Ui ui, Scene *&chosen) {
  $cui.row(ui, { .width = CUI_FILL, .height = CUI_FILL,
                 .bg = CUI_COLOR_BACKGROUND }) {
    $cui.scroll(ui, { .id = "scenes", .width = CUI_PX(220),
                      .height = CUI_FILL, .pad = 12, .gap = 2 }) {
      for (int f = 0; f < family_count(); f++) {
        ui.nav_section(families[f].title);
        for (int s = 0; s < families[f].count; s++) {
          Scene *scene = &families[f].scenes[s];
          if (ui.nav_item(scene.name, { .selected = scene == chosen }))
            chosen = scene;
        }
      }
    }
    ui.separator();
    // The scene's name scopes its ids, so scenes keep separate state.
    $cui.id_scope(ui, chosen.name) draw_page(ui, chosen);
  }
}

int main(int argc, char **argv) {
  add_families();
  if (argc == 2 && !strcmp(argv[1], "--list")) return list_scenes();
  if (argc >= 3 && !strcmp(argv[1], "--shots"))
    return shoot_scenes(argv[2], argc > 3 ? argv[3] : NULL);

  Scene *chosen = &families[0].scenes[0];
  App app = auto App.open({ .title = "x2cui gallery", .width = 1080,
                            .height = 720 });
  while (app.frame()) draw_browser(app.ui(), chosen);
  return 0;
}
