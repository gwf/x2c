/*  test-path.x -- unit tests for filesystem operations on Paths */

#include "path.x"
#include "test-support.x"
$(import "test-macros.xmacro")
#include <errno.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static void path_parts_examine_text(void) {
  $test.scoped();
  Path archive = "a/b/c.tar.gz";
  EXPECT_STR_EQ(archive.dirname(), "a/b");
  EXPECT_STR_EQ(archive.basename(), "c.tar.gz");
  EXPECT_STR_EQ(archive.stem(), "c.tar");
  EXPECT_STR_EQ(archive.extension(), ".gz");
  EXPECT_STR_EQ(Path.dirname("c"), ".");
  EXPECT_STR_EQ(Path.dirname("/c"), "/");
  EXPECT_STR_EQ(Path.basename("/"), "/");
  EXPECT_STR_EQ(Path.dirname("a//b//"), "a");
  EXPECT_STR_EQ(Path.basename("a//b//"), "b");
  EXPECT_STR_EQ(Path.stem(".bashrc"), ".bashrc");
  EXPECT_NULL(Path.extension(".bashrc"));
  EXPECT_NULL(Path.extension(".."));
  EXPECT_STR_EQ(Path.stem(".."), "..");
  EXPECT_NULL(Path.extension("/x/.."));
  EXPECT_STR_EQ(Path.stem("/x/.."), "..");
  EXPECT_NULL(Path.extension("notes."));
  EXPECT_STR_EQ(Path.stem("notes."), "notes.");
  EXPECT_STR_EQ(Path.join("a", "b"), "a/b");
  EXPECT_STR_EQ(Path.join("a/", "b"), "a/b");
  EXPECT_STR_EQ(Path.join("a", "/b"), "/b");
  EXPECT_STR_EQ(Path.join(NULL, "b"), "b");
}

static long _text_length(String text) => text.len();

static void path_values_act_as_strings(void) {
  $test.scoped();
  Path path = "src/parse.x", same = %"src/${"parse"}.x";
  Var boxed = path;
  EXPECT_TRUE(boxed is String);
  EXPECT_STR_EQ(boxed.str(), "src/parse.x");
  Map seen = {};
  seen[path] = 1;
  EXPECT_TRUE(seen.contains(same) && seen.contains("src/parse.x"));
  EXPECT_STR_EQ(path.repr(), "\"src/parse.x\"");
  EXPECT_STR_EQ(%"<$path>", "<src/parse.x>");
  EXPECT_INT_EQ(_text_length(path), 11);
  EXPECT_TRUE(path == same && path == "src/parse.x" && path != "src");
  foreach (Path unit, %("a/b.x")) EXPECT_STR_EQ(unit.stem(), "b");
}

static void path_glob_match_follows_components(void) {
  $test.scoped();
  Path pattern = "src/**/*.x";
  EXPECT_TRUE(pattern.glob_match("src/main.x"));
  EXPECT_TRUE(pattern.glob_match("src/a/b/main.x"));
  EXPECT_FALSE(pattern.glob_match("src/main.c"));
  EXPECT_FALSE(Path.glob_match("src/**/main.x", "src/xmain.x"));
  EXPECT_FALSE(Path.glob_match("*.x", "src/main.x"));
  EXPECT_TRUE(Path.glob_match("file[0-9].?", "file7.c"));
  EXPECT_FALSE(Path.glob_match("file[!0-9].c", "file7.c"));
  EXPECT_FALSE(Path.glob_match("*", ".hidden"));
  EXPECT_FALSE(Path.glob_match("src/*.x", "src/.draft.x"));
  EXPECT_FALSE(Path.glob_match("**/*.x", ".git/objects/a.x"));
  EXPECT_FALSE(Path.glob_match("a/**", "a/.h/x"));
  EXPECT_TRUE(Path.glob_match("tree/**/.hid/*.x", "tree/.hid/e.x"));
  EXPECT_TRUE(Path.glob_match(".*", ".hidden"));
  EXPECT_TRUE(Path.glob_match("src/.draft.*", "src/.draft.x"));
  EXPECT_TRUE(Path.glob_match("\\.hidden", ".hidden"));
  EXPECT_TRUE(Path.glob_match("a\\*b", "a*b"));
  EXPECT_FALSE(Path.glob_match("a\\*b", "axb"));
  EXPECT_TRUE(Path.glob_match("[]a].x", "].x"));
  EXPECT_TRUE(Path.glob_match("[!]]*.x", "a.x"));
  EXPECT_FALSE(Path.glob_match("[!]]*.x", "].x"));
  EXPECT_TRUE(Path.glob_match("src//*.x", "src/a.x"));
  EXPECT_TRUE(Path.glob_match("src/*.x", "src//a.x"));
  EXPECT_FALSE(Path.glob_match("src/*.x", "src/.a.x"));
  String letters = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  clock_t start = clock();
  EXPECT_FALSE(Path.glob_match("*a*a*a*a*a*a*a*a*a*a*b", letters));
  EXPECT_TRUE(Path.glob_match("*a*a*a*a*a*a*a*a*a*a", letters));
  EXPECT_TRUE(clock() - start < CLOCKS_PER_SEC / 10);
  Path deep = "**/**/**/**/**/**/z";
  EXPECT_FALSE(deep.glob_match(
    "a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y"));
}

static void path_tree_operations(void) {
  $test.scoped();
  Path root = Path.temp_dir();
  EXPECT_TRUE(root.is_dir());
  Path deep = root.join("one/two");
  deep.make_dirs();
  deep.make_dirs();
  EXPECT_TRUE(deep.is_dir());
  Path file = deep.join("f.x");
  file.write_text("hello\n");
  root.join("one/g.x").write_text("gee\n");
  EXPECT_STR_EQ(file.read_text(), "hello\n");
  EXPECT_INT_EQ(file.size(), 6);
  EXPECT_TRUE(file.modified_time() > 0);
  struct timeval times[2] = { { 1000, 500000 }, { 1000, 500000 } };
  EXPECT_INT_EQ(utimes(file, times), 0);
  EXPECT_TRUE(file.modified_time() == 1000.5);
  EXPECT_TRUE(file.is_file() && !file.is_dir() && file.exists());
  EXPECT_LIST_EQ(root.join("one").list_dir(), %("g.x" "two"));

  List walked = root.walk().map(%!(path) => path.str()[root.len():]);
  EXPECT_LIST_EQ(walked, %("/one" "/one/g.x" "/one/two" "/one/two/f.x"));
  EXPECT_LIST_EQ(Path.glob(%"$root/**/*.x"),
                 %(${%"$root/one/g.x"} ${%"$root/one/two/f.x"}));
  EXPECT_LIST_EQ(Path.glob(%"$root/one/*.x"), %(${%"$root/one/g.x"}));
  EXPECT_LIST_EQ(root.join("one").glob(), %(${root.join("one")}));
  EXPECT_NULL(Path.glob(%"$root/*.none"));
  root.join(".hidden").make_dirs();
  root.join(".hidden/h.x").write_text("h\n");
  EXPECT_LIST_EQ(Path.glob(%"$root/**/*.x"),
                 %(${%"$root/one/g.x"} ${%"$root/one/two/f.x"}));
  EXPECT_LIST_EQ(Path.glob(%"$root/.*/*.x"), %(${%"$root/.hidden/h.x"}));
  EXPECT_LIST_EQ(Path.glob(%"$root/**/.hidden/*.x"),
                 %(${%"$root/.hidden/h.x"}));
  char *cwd = getcwd(NULL, 0);
  chdir(root);
  EXPECT_LIST_EQ(Path.glob(".*/*.x"), %(".hidden/h.x"));
  chdir(cwd);
  free(cwd);
  root.join(".hidden").remove_tree();

  chmod(file, 0640);
  root.join("one").copy_tree(root.join("copy"));
  Path copied = root.join("copy/two/f.x");
  EXPECT_STR_EQ(copied.read_text(), "hello\n");
  struct stat info;
  EXPECT_INT_EQ(stat(copied, &info), 0);
  EXPECT_INT_EQ(info.st_mode & 0777, 0640);

  root.join("copy/g.x").move_to(root.join("moved.x"));
  EXPECT_FALSE(root.join("copy/g.x").exists());
  EXPECT_STR_EQ(root.join("moved.x").read_text(), "gee\n");
  root.join("link").symlink_to("one");
  EXPECT_TRUE(root.join("link/g.x").is_file());
  EXPECT_STR_EQ(root.join("link/../copy").absolute(),
                root.join("copy").absolute());
  EXPECT_STR_EQ(root.join("copy/./missing/../new").absolute(),
                root.join("copy").absolute().join("new"));

  root.join("moved.x").remove_file();
  root.join("moved.x").remove_file();
  EXPECT_FALSE(root.join("moved.x").exists());
  root.join("link").remove_tree();
  EXPECT_TRUE(root.join("one/g.x").exists());
  root.remove_tree();
  root.remove_tree();
  EXPECT_FALSE(root.exists());
}

static void path_failures_raise_with_details(void) {
  $test.scoped();
  Path root = Path.temp_dir(), missing = root.join("missing");
  int caught = 0;
  try missing.list_dir();
  catch %(not-found *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), "Path.list_dir");
    EXPECT_STR_EQ(detail.assoc(<path>).string(), missing);
  }
  try missing.join("x").write_text("x");
  catch %(not-found (operation "Path.write_text") *): caught++;
  try missing.read_text();
  catch %(not-found (operation "Path.read_text") *): caught++;
  try missing.copy_file(root.join("copy"));
  catch %(not-found (operation "Path.copy_file") *): caught++;
  try missing.size();
  catch %(not-found *): caught++;
  Path file = root.join("file");
  file.write_text("x");
  try file.join("below").make_dirs();
  catch %(io-fail *): caught++;
  try file.make_dirs();
  catch %(io-fail *detail): {
    caught++;
    EXPECT_INT_EQ(detail.assoc(<errno>).integer(), ENOTDIR);
  }
  Path dir = root.join("dir"), target = root.join("target");
  dir.make_dirs();
  try dir.read_text();
  catch %(io-fail *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), "Path.read_text");
    EXPECT_STR_EQ(detail.assoc(<path>).string(), dir);
    EXPECT_INT_EQ(detail.assoc(<errno>).integer(), EISDIR);
  }
  try dir.copy_file(target);
  catch %(io-fail *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), "Path.copy_file");
    EXPECT_STR_EQ(detail.assoc(<path>).string(), dir);
  }
  EXPECT_FALSE(target.exists());
  EXPECT_INT_EQ(caught, 9);
  root.remove_tree();
}

static void path_glob_follows_the_shell(void) {
  $test.scoped();
  Path root = Path.temp_dir();
  root.join("src/a").make_dirs();
  root.join("src/b").make_dirs();
  root.join("src/f.x").write_text("f");
  root.join("src/a/g.x").write_text("g");
  root.join("a.x").write_text("a");
  root.join("].x").write_text("b");
  char *cwd = getcwd(NULL, 0);
  chdir(root);
  try {
    EXPECT_LIST_EQ(Path.glob("src/*/"), %("src/a/" "src/b/"));
    EXPECT_LIST_EQ(Path.glob("src//*.x"), %("src//f.x"));
    EXPECT_LIST_EQ(Path.glob("src/*//*.x"), %("src/a/g.x"));
    EXPECT_LIST_EQ(Path.glob("[]a].x"), %("].x" "a.x"));
    EXPECT_LIST_EQ(Path.glob("*/"), %("src/"));
    EXPECT_LIST_EQ(Path.glob("src/*"), %("src/a" "src/b" "src/f.x"));
  }
  finally {
    chdir(cwd);
    free(cwd);
    root.remove_tree();
  }
}

static void path_copies_refuse_to_destroy_their_source(void) {
  $test.scoped();
  Path root = Path.temp_dir(), file = root.join("f.txt");
  file.write_text("hello");
  file.copy_file(file);
  EXPECT_STR_EQ(file.read_text(), "hello");
  root.join("link").symlink_to("f.txt");
  root.join("link").copy_file(file);
  EXPECT_STR_EQ(file.read_text(), "hello");

  Path tree = root.join("x");
  tree.join("y").make_dirs();
  tree.join("y/z").write_text("z");
  int caught = 0;
  try tree.copy_tree(tree.join("y/copy"));
  catch %(io-fail *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), "Path.copy_tree");
    EXPECT_INT_EQ(detail.assoc(<errno>).integer(), EINVAL);
  }
  try tree.copy_tree(tree);
  catch %(io-fail *): caught++;
  EXPECT_INT_EQ(caught, 2);
  EXPECT_FALSE(tree.join("y/copy").exists());
  tree.copy_tree(root.join("xx"));
  EXPECT_STR_EQ(root.join("xx/y/z").read_text(), "z");
  root.remove_tree();
}

static void path_reports_executable_permission(void) {
  $test.scoped();
  Path root = Path.temp_dir();
  Path script = root.join("run.sh");
  script.write_text("#!/bin/sh\nexit 0\n");
  EXPECT_TRUE(script.is_file() && !script.is_executable());
  chmod(script, 0755);
  EXPECT_TRUE(script.is_executable());
  // `-x` asks about search permission too, so a directory qualifies.
  EXPECT_TRUE(root.is_executable());
  EXPECT_TRUE(!root.join("absent").is_executable());
  EXPECT_TRUE(!Path.is_executable(NULL));
  root.remove_tree();
}

void path_suite(void) {
  $test.run(path_parts_examine_text);
  $test.run(path_values_act_as_strings);
  $test.run(path_glob_match_follows_components);
  $test.run(path_glob_follows_the_shell);
  $test.run(path_copies_refuse_to_destroy_their_source);
  $test.run(path_tree_operations);
  $test.run(path_reports_executable_permission);
  $test.run(path_failures_raise_with_details);
}
