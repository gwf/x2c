/*  scenes.x -- One small scene for every CUI component, drawn off screen.

    Each scene draws one component the way a program would use it. A scene
    is named for its CUI component: the scene `button` shows `ui.button`,
    and the scene `row` shows `ui.row`. The files under scenes/ group
    the scenes into families. The package's check draws them all, which
    shows that every component has an x2c form and draws.

    gallery.x is the application to browse; this program opens no window.

      scenes --list               print the scene names, one a line
      scenes --shots DIR [SCENE]  draw every scene, or one, to DIR/NAME.png
      scenes --check HEADER       compare the scene names with the
                                  components that CUI's cui.h defines
*/

#include "path.x"
#include "scenes/scene.x"
#include "scenes/layout.x"
#include "scenes/controls.x"
#include "scenes/display.x"
#include "scenes/media.x"
#include "scenes/data.x"
#include "scenes/viz.x"
#include "scenes/devtools.x"
#include "scenes/choices.x"
#include "scenes/tools.x"
#include "scenes/chrome.x"

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
  add_family(viz_family());
  add_family(devtools_family());
  add_family(choices_family());
  add_family(tools_family());
  add_family(chrome_family());
}

// The page every scene is drawn on.
static void draw_page(Ui ui, Scene *scene) {
  ui.column (width: CUI_FILL, height: CUI_FILL, pad: 28,
             gap: 16, bg: CUI_COLOR_BACKGROUND)
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

/* Compares the scene names with the components of CUI's header, where
   each `#define cui_NAME(` line defines the component NAME. */
static int check_scenes(Path header) {
  Map scenes = {}, components = {};
  for (int f = 0; f < family_count(); f++)
    for (int s = 0; s < families[f].count; s++)
      scenes[families[f].scenes[s].name] = 1;
  int unmatched = 0;
  Var found;
  foreach (String line in header.read_text().split_lines(0)) {
    if (!line.startswith("#define cui_")) continue;
    String rest = line.remove_prefix("#define cui_");
    int paren = rest.find("(");
    if (paren < 0) continue;
    String name = rest[:paren];
    components[name] = 1;
    if (scenes.try_get(name, found)) continue;
    printf("component %s has no scene\n", name);
    unmatched++;
  }
  foreach (String name in scenes.keys()) {
    if (components.try_get(name, found)) continue;
    printf("scene %s names no component\n", name);
    unmatched++;
  }
  printf("%d components, %d scenes, %d unmatched\n",
         (int) components.len(), (int) scenes.len(), unmatched);
  return unmatched ? 1 : 0;
}

int main(int argc, char **argv) {
  add_families();
  if (argc == 2 && !strcmp(argv[1], "--list")) return list_scenes();
  if (argc >= 3 && !strcmp(argv[1], "--shots"))
    return shoot_scenes(argv[2], argc > 3 ? argv[3] : NULL);
  if (argc == 3 && !strcmp(argv[1], "--check"))
    return check_scenes(argv[2]);
  printf("usage: scenes --list | --shots DIR [SCENE] | --check HEADER\n");
  return 2;
}
