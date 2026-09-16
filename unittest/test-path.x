/*  test-path.x -- unit tests for filesystem operations on path Strings */

#include "path.x"
#include "test-support.x"
$(import "test-macros.xmacro")
#include <errno.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

static void path_parts_examine_text(void) {
  $test.scoped();
  String archive = "a/b/c.tar.gz";
  EXPECT_STR_EQ(archive.dirname(), "a/b");
  EXPECT_STR_EQ(archive.basename(), "c.tar.gz");
  EXPECT_STR_EQ(archive.stem(), "c.tar");
  EXPECT_STR_EQ(archive.extension(), ".gz");
  EXPECT_STR_EQ(%"c".dirname(), ".");
  EXPECT_STR_EQ(%"/c".dirname(), "/");
  EXPECT_STR_EQ(%"/".basename(), "/");
  EXPECT_STR_EQ(%"a//b//".dirname(), "a");
  EXPECT_STR_EQ(%"a//b//".basename(), "b");
  EXPECT_STR_EQ(%".bashrc".stem(), ".bashrc");
  EXPECT_NULL(%".bashrc".extension());
  EXPECT_STR_EQ(%"a".join_path("b"), "a/b");
  EXPECT_STR_EQ(%"a/".join_path("b"), "a/b");
  EXPECT_STR_EQ(%"a".join_path("/b"), "/b");
  EXPECT_STR_EQ(((String) NULL).join_path("b"), "b");
}

static void path_glob_match_follows_components(void) {
  $test.scoped();
  String pattern = "src/**/*.x";
  EXPECT_TRUE(pattern.glob_match("src/main.x"));
  EXPECT_TRUE(pattern.glob_match("src/a/b/main.x"));
  EXPECT_FALSE(pattern.glob_match("src/main.c"));
  EXPECT_FALSE(%"src/**/main.x".glob_match("src/xmain.x"));
  EXPECT_FALSE(%"*.x".glob_match("src/main.x"));
  EXPECT_TRUE(%"file[0-9].?".glob_match("file7.c"));
  EXPECT_FALSE(%"file[!0-9].c".glob_match("file7.c"));
  EXPECT_FALSE(%"*".glob_match(".hidden"));
  EXPECT_FALSE(%"src/*.x".glob_match("src/.draft.x"));
  EXPECT_FALSE(%"**/*.x".glob_match(".git/objects/a.x"));
  EXPECT_TRUE(%".*".glob_match(".hidden"));
  EXPECT_TRUE(%"src/.draft.*".glob_match("src/.draft.x"));
  EXPECT_TRUE(%"\\.hidden".glob_match(".hidden"));
  EXPECT_TRUE(%"a\\*b".glob_match("a*b"));
  EXPECT_FALSE(%"a\\*b".glob_match("axb"));
  String deep = %"**/**/**/**/**/**/z";
  EXPECT_FALSE(deep.glob_match(
    "a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y"));
}

static void path_tree_operations(void) {
  $test.scoped();
  String root = String.temp_dir();
  EXPECT_TRUE(root.is_dir());
  String deep = root.join_path("one/two");
  deep.make_dirs();
  deep.make_dirs();
  EXPECT_TRUE(deep.is_dir());
  String file = deep.join_path("f.x");
  file.write_text("hello\n");
  root.join_path("one/g.x").write_text("gee\n");
  EXPECT_STR_EQ(file.read_text(), "hello\n");
  EXPECT_INT_EQ(file.file_size(), 6);
  EXPECT_TRUE(file.modified_time() > 0);
  struct timeval times[2] = { { 1000, 500000 }, { 1000, 500000 } };
  EXPECT_INT_EQ(utimes(file, times), 0);
  EXPECT_TRUE(file.modified_time() == 1000.5);
  EXPECT_TRUE(file.is_file() && !file.is_dir() && file.exists());
  EXPECT_LIST_EQ(root.join_path("one").list_dir(), %("g.x" "two"));

  List walked = root.walk().map(%!(path) => path.str()[root.len():]).list();
  EXPECT_LIST_EQ(walked, %("/one" "/one/g.x" "/one/two" "/one/two/f.x"));
  EXPECT_LIST_EQ(%"$root/**/*.x".glob(),
                 %(${%"$root/one/g.x"} ${%"$root/one/two/f.x"}));
  EXPECT_LIST_EQ(%"$root/one/*.x".glob(), %(${%"$root/one/g.x"}));
  EXPECT_LIST_EQ(root.join_path("one").glob(), %(${root.join_path("one")}));
  EXPECT_NULL(%"$root/*.none".glob());
  root.join_path(".hidden").make_dirs();
  root.join_path(".hidden/h.x").write_text("h\n");
  EXPECT_LIST_EQ(%"$root/**/*.x".glob(),
                 %(${%"$root/one/g.x"} ${%"$root/one/two/f.x"}));
  EXPECT_LIST_EQ(%"$root/.*/*.x".glob(), %(${%"$root/.hidden/h.x"}));
  char *cwd = getcwd(NULL, 0);
  chdir(root);
  EXPECT_LIST_EQ(%".*/*.x".glob(), %(".hidden/h.x"));
  chdir(cwd);
  free(cwd);
  root.join_path(".hidden").remove_tree();

  chmod(file, 0640);
  root.join_path("one").copy_tree(root.join_path("copy"));
  String copied = root.join_path("copy/two/f.x");
  EXPECT_STR_EQ(copied.read_text(), "hello\n");
  struct stat info;
  EXPECT_INT_EQ(stat(copied, &info), 0);
  EXPECT_INT_EQ(info.st_mode & 0777, 0640);

  root.join_path("copy/g.x").move_to(root.join_path("moved.x"));
  EXPECT_FALSE(root.join_path("copy/g.x").exists());
  EXPECT_STR_EQ(root.join_path("moved.x").read_text(), "gee\n");
  root.join_path("link").symlink_to("one");
  EXPECT_TRUE(root.join_path("link/g.x").is_file());
  EXPECT_STR_EQ(root.join_path("link/../copy").absolute_path(),
                root.join_path("copy").absolute_path());
  EXPECT_STR_EQ(root.join_path("copy/./missing/../new").absolute_path(),
                root.join_path("copy").absolute_path().join_path("new"));

  root.join_path("moved.x").remove_file();
  root.join_path("moved.x").remove_file();
  EXPECT_FALSE(root.join_path("moved.x").exists());
  root.join_path("link").remove_tree();
  EXPECT_TRUE(root.join_path("one/g.x").exists());
  root.remove_tree();
  root.remove_tree();
  EXPECT_FALSE(root.exists());
}

static void path_failures_raise_with_details(void) {
  $test.scoped();
  String root = String.temp_dir(), missing = root.join_path("missing");
  int caught = 0;
  try missing.list_dir();
  catch %(not-found *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), "String.list_dir");
    EXPECT_STR_EQ(detail.assoc(<path>).string(), missing);
  }
  try missing.join_path("x").write_text("x");
  catch %(not-found *): caught++;
  try missing.file_size();
  catch %(not-found *): caught++;
  String file = root.join_path("file");
  file.write_text("x");
  try file.join_path("below").make_dirs();
  catch %(io-fail *): caught++;
  try file.make_dirs();
  catch %(io-fail *detail): {
    caught++;
    EXPECT_INT_EQ(detail.assoc(Symbol.new("errno")).integer(), ENOTDIR);
  }
  EXPECT_INT_EQ(caught, 5);
  root.remove_tree();
}

static void path_reports_executable_permission(void) {
  $test.scoped();
  String root = String.temp_dir();
  String script = root.join_path("run.sh");
  script.write_text("#!/bin/sh\nexit 0\n");
  EXPECT_TRUE(script.is_file() && !script.is_executable());
  chmod(script, 0755);
  EXPECT_TRUE(script.is_executable());
  // `-x` asks about search permission too, so a directory qualifies.
  EXPECT_TRUE(root.is_executable());
  EXPECT_TRUE(!root.join_path("absent").is_executable());
  EXPECT_TRUE(!String.is_executable(NULL));
  root.remove_tree();
}

void path_suite(void) {
  $test.run(path_parts_examine_text);
  $test.run(path_glob_match_follows_components);
  $test.run(path_tree_operations);
  $test.run(path_reports_executable_permission);
  $test.run(path_failures_raise_with_details);
}
