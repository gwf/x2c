/*  path.x -- filesystem locations and the operations on them

    Copyright (c) 2026 Gary William Flake

    A `Path` is a `String` that names a filesystem location; its methods read
    and change the files it names. A failure raises `<not-found>` when a
    named path does not exist and `<io-fail>` for any other host failure,
    both with `operation`, `path`, and `errno` details. Removing a path that
    is already absent succeeds.

    The path-part methods only examine text. `dirname` and `basename` follow
    POSIX, ignoring trailing slashes. Glob patterns use `*` and `?` within
    one path component, `[...]` character classes, `**` for any number of
    components, and backslash to quote the next character. As in a shell, a
    wildcard does not match a leading dot; spell the dot to match it.
*/

#pragma once
#include "x2c.x"

/** A `String` that names a filesystem location. A literal or a `String`
    converts to a `Path` wherever one is expected, and a `Path` passes
    wherever a `String` is expected. Slicing and `+` are `String` operations.
*/
class Path String;

#pragma private

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void _path_error(const char *operation, String path, int error) {
  String name = operation;
  if (error == ENOENT)
    raise %(not-found (operation $name) (path $path) (errno $error));
  raise %(io-fail (operation $name) (path $path) (errno $error));
}

static String _trimmed(String path) {
  int length = path.len();
  while (length > 1 && path[length - 1] == '/') length--;
  return path[:length];
}

/** Returns `name` joined to `base` with one separating slash.
    An absolute `name`, or an empty `base`, is returned unchanged.
*/
Self Path.join(Self base, Path name) {
  if (!name) return base;
  if (!base || name.startswith("/")) return name;
  return base.endswith("/") ? %"$base$name" : %"$base/$name";
}

/** Returns the directory part of `path`: `.` when it has no slash and `/`
    for a path directly under the root.
*/
Self Path.dirname(Self path) {
  String trimmed = _trimmed(path);
  int slash = trimmed.rfind("/");
  if (slash < 0) return ".";
  while (slash > 0 && trimmed[slash - 1] == '/') slash--;
  return slash ? trimmed[:slash] : "/";
}

/** Returns the last component of `path`, ignoring trailing slashes. */
Self Path.basename(Self path) {
  String trimmed = _trimmed(path);
  if (trimmed == "/") return trimmed;
  int slash = trimmed.rfind("/");
  return slash < 0 ? trimmed : trimmed[slash + 1:];
}

/** Returns the extension of `path`'s last component, including its dot, or
    NULL when there is none. A leading dot does not start an extension.
*/
String Path.extension(Path path) {
  String base = path.basename();
  int dot = base.rfind(".");
  return dot > 0 ? base[dot:] : NULL;
}

/** Returns `path`'s last component without its extension. */
String Path.stem(Path path) {
  String base = path.basename();
  int dot = base.rfind(".");
  return dot > 0 ? base[:dot] : base;
}

/** Returns an absolute form of `path` with symbolic links resolved.
    Missing trailing components are appended to their resolved parent with
    `.` and `..` normalized, so a path that does not exist yet still has a
    stable identity.
    Raises: `<io-fail>` when a relative path needs the current directory and
    it cannot be read.
*/
Self Path.absolute(Self path) {
  char buffer[PATH_MAX];
  if (realpath(path, buffer)) return String.new(buffer);
  if (!path.startswith("/")) {
    if (!getcwd(buffer, sizeof(buffer)))
      _path_error("Path.absolute", path, errno);
    path = Path.join(String.new(buffer), path);
  }
  Path result = "/";
  foreach (String part, path.split("/")) {
    if (!part || part == ".") continue;
    if (part == "..") {
      result = result.dirname();
      continue;
    }
    result = result.join(part);
    if (realpath(result, buffer)) result = String.new(buffer);
  }
  return result;
}

/** Reports whether `path` names an existing file, following links. */
int Path.exists(Path path) {
  struct stat info;
  return path && stat(path, &info) == 0;
}

/** Reports whether `path` names a directory, following links. */
int Path.is_dir(Path path) {
  struct stat info;
  return path && stat(path, &info) == 0 && S_ISDIR(info.st_mode);
}

/** Reports whether `path` names a regular file, following links. */
int Path.is_file(Path path) {
  struct stat info;
  return path && stat(path, &info) == 0 && S_ISREG(info.st_mode);
}

/** Reports whether this process may execute `path`, as the shell's `-x`. */
int Path.is_executable(Path path) => path && access(path, X_OK) == 0;

static struct stat _stat(const char *operation, String path) {
  struct stat info;
  if (stat(path, &info)) _path_error(operation, path, errno);
  return info;
}

/** Returns the size of the file at `path` in bytes.
    Raises: `<not-found>` or `<io-fail>`.
*/
long Path.size(Path path) => (long) _stat("Path.size", path).st_size;

/** Returns the modification time of `path` in seconds since the epoch,
    with the fraction the filesystem records.
    Raises: `<not-found>` or `<io-fail>`.
*/
double Path.modified_time(Path path) {
  struct stat info = _stat("Path.modified_time", path);
#ifdef __APPLE__
  return info.st_mtimespec.tv_sec + info.st_mtimespec.tv_nsec / 1e9;
#else
  return info.st_mtim.tv_sec + info.st_mtim.tv_nsec / 1e9;
#endif
}

/** Returns the names in the directory `path`, sorted, without `.` and `..`.
    Raises: `<not-found>` or `<io-fail>`.
*/
List Path.list_dir(Path path) {
  DIR *directory = opendir(path);
  if (!directory) _path_error("Path.list_dir", path, errno);
  Array names = [], struct dirent *entry;
  while ((entry = readdir(directory)))
    if (strcmp(entry->d_name, ".") && strcmp(entry->d_name, ".."))
      names.push(String.new(entry->d_name));
  closedir(directory);
  return names.sort().list_free();
}

static int _descends(String path) {
  struct stat info;
  return lstat(path, &info) == 0 && S_ISDIR(info.st_mode) &&
         access(path, R_OK | X_OK) == 0;
}

/* Pushes a directory's children so the next pop yields the first sorted
   name. */
static void _push_children(Array pending, Path directory) {
  List children = directory.list_dir().reverse();
  foreach (String name, children) pending.push(directory.join(name));
}

static int _walk_next(Iter iter, Var *out) {
  Array pending = iter.state;
  if (!pending || !pending.len()) return 0;
  String path = pending.take_last();
  if (_descends(path)) _push_children(pending, path);
  *out = path;
  return 1;
}

/** Returns a lazy iterator over every path below the directory `root`,
    parents before their contents and siblings sorted. Symbolic links to
    directories are listed but not followed, and a directory that cannot be
    read is listed without its contents. Only the paths not yet visited are
    held; the yielded paths live in the active pool.

    ```x2c
    ~#include "path.x"
    ~int main(void) {
    Path source = "src";
    foreach (Path path, source.walk()) printf("%s\n", path);
    long units = source.walk().filter(%!(p) => p.str().endswith(".x")).count();
    ~  return units >= 0 ? 0 : 1;
    ~}
    ```

    Raises: `<not-found>` or `<io-fail>` when `root` cannot be listed, and
    `<io-fail>` from a pull when a directory vanishes during the walk.
*/
Iter Path.walk(Path root, Iter dest) {
  Array pending = [];
  _push_children(pending, root);
  return dest.init((Var) {0}, _walk_next, pending);
}

static void _walk(Path directory, int depth, int hidden, Array paths) {
  foreach (String name, directory.list_dir()) {
    Path child = directory.join(name);
    paths.push(child);
    if (depth != 1 && (hidden || !name.startswith(".")) && _descends(child))
      _walk(child, depth - 1, hidden, paths);
  }
}

static int _class_match(const char **pattern, unsigned char value) {
  const char *ch = *pattern, int negate = *ch == '!' || *ch == '^';
  if (negate) ch++;
  int matched = 0;
  while (*ch && *ch != ']') {
    unsigned char first = *ch++;
    if (*ch == '-' && ch[1] && ch[1] != ']') {
      ch++;
      unsigned char last = *ch++;
      if (value >= first && value <= last) matched = 1;
    }
    else if (value == first) matched = 1;
  }
  if (*ch != ']') return -1;
  *pattern = ch + 1;
  return negate ? !matched : matched;
}

/* A name that begins with a dot matches only a pattern that spells the dot,
   as in a shell: no wildcard matches a component's leading dot. */
static int _glob_match(
  const char *pattern, const char *text, const char *origin) {
  if (!*pattern) return !*text;
  if (*text == '.' && (text == origin || text[-1] == '/') &&
      *pattern != '.' && !(pattern[0] == '\\' && pattern[1] == '.'))
    return 0;
  if (pattern[0] == '*' && pattern[1] == '*') {
    const char *rest = pattern + 2;
    int components = *rest == '/';
    while (components && rest[1] == '*' && rest[2] == '*' && rest[3] == '/')
      rest += 3;
    for (const char *ch = text;; ch++) {
      if ((!components || ch == text || ch[-1] == '/') &&
          _glob_match(rest + components, ch, origin))
        return 1;
      if (!*ch) return 0;
    }
  }
  if (*pattern == '*') {
    pattern++;
    if (_glob_match(pattern, text, origin)) return 1;
    return *text && *text != '/' &&
           _glob_match(pattern - 1, text + 1, origin);
  }
  if (*pattern == '?')
    return *text && *text != '/' &&
           _glob_match(pattern + 1, text + 1, origin);
  if (*pattern == '[') {
    if (!*text || *text == '/') return 0;
    const char *rest = pattern + 1;
    int matched = _class_match(&rest, (unsigned char) *text);
    if (matched < 0)
      return *text == '[' && _glob_match(pattern + 1, text + 1, origin);
    return matched && _glob_match(rest, text + 1, origin);
  }
  if (*pattern == '\\' && pattern[1]) pattern++;
  return *pattern == *text && _glob_match(pattern + 1, text + 1, origin);
}

/** Reports whether all of `path` matches the glob `pattern`. A path
    component that begins with a dot matches only a pattern component that
    begins with one.
*/
int Path.glob_match(Path pattern, Path path) =>
  pattern && path && _glob_match(pattern, path, path);

/** Returns the existing paths that match the glob `pattern`, sorted.
    The walk starts at the longest leading directory without a wildcard and
    descends only as deep as the pattern can match. As in a shell, a name
    that begins with a dot matches only where the pattern spells the dot.
    No match returns an empty `List`.
*/
List Path.glob(Path pattern) {
  if (!strpbrk(pattern, "*?[\\"))
    return pattern.exists() ? %($pattern) : NULL;
  List parts = pattern.split("/");
  Path base = NULL;
  int depth = 0, recursive = 0;
  foreach (String part, parts) {
    if (depth || strpbrk(part ? part : "", "*?[\\")) {
      depth++;
      if (part == "**") recursive = 1;
    }
    else base = base ? base.join(part) : part ? part : "/";
  }
  Path root = base ? base : ".";
  Array paths = [], matches = [];
  if (root.is_dir())
    _walk(root, recursive ? -1 : depth,
          pattern.startswith(".") || pattern.contains("/."), paths);
  foreach (String path, paths) {
    String candidate = base ? path : path[2:];
    if (pattern.glob_match(candidate)) matches.push(candidate);
  }
  return matches.sort().list_free();
}

/** Creates the directory `path` and any missing parents.
    An existing directory is left as it is.
    Raises: `<io-fail>` when a component cannot be created or `path` names
    an existing non-directory, or `<not-found>`.
*/
void Path.make_dirs(Path path) {
  char buffer[PATH_MAX];
  if (path.len() >= sizeof(buffer))
    _path_error("Path.make_dirs", path, ENAMETOOLONG);
  strcpy(buffer, path);
  for (char *ch = buffer + 1; *ch; ch++) {
    if (*ch != '/') continue;
    *ch = 0;
    if (mkdir(buffer, 0777) && errno != EEXIST)
      _path_error("Path.make_dirs", String.new(buffer), errno);
    *ch = '/';
  }
  if (mkdir(buffer, 0777) && errno != EEXIST)
    _path_error("Path.make_dirs", path, errno);
  if (!path.is_dir()) _path_error("Path.make_dirs", path, ENOTDIR);
}

/** Removes the file or symbolic link `path` when it exists.
    Raises: `<io-fail>` when it exists and cannot be removed.
*/
void Path.remove_file(Path path) {
  if (unlink(path) && errno != ENOENT)
    _path_error("Path.remove_file", path, errno);
}

static void _remove_tree(Path path, String *failed, int *failure) {
  struct stat info;
  if (lstat(path, &info)) {
    if (errno != ENOENT && !*failed) *failed = path, *failure = errno;
    return;
  }
  if (S_ISDIR(info.st_mode)) {
    DIR *directory = opendir(path);
    if (directory) {
      struct dirent *entry;
      while ((entry = readdir(directory))) {
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, ".."))
          continue;
        // Each entry's paths are released before the next, however large
        // the tree; only a reported failure's path is kept.
        Context context = $auto(Context.open_isolated());
        String child_failed = NULL;
        int child_failure = 0;
        _remove_tree(
          path.join(String.new(entry->d_name)), &child_failed,
          &child_failure);
        if (child_failed && !*failed) {
          *failed = context.export(child_failed);
          *failure = child_failure;
        }
      }
      closedir(directory);
    }
    if (rmdir(path) && !*failed) *failed = path, *failure = errno;
  }
  else if (unlink(path) && !*failed) *failed = path, *failure = errno;
}

/** Removes `path` and everything below it when it exists.
    Symbolic links are removed, not followed. Removal continues past an
    entry that cannot be removed.
    Raises: `<io-fail>` naming the first path that could not be removed.
*/
void Path.remove_tree(Path path) {
  String failed = NULL;
  int failure = 0;
  _remove_tree(path, &failed, &failure);
  if (failed) raise %(io-fail (operation "Path.remove_tree")
                      (path $failed) (errno $failure));
}

/** Copies the regular file `source` to `target`, replacing `target` and
    giving it `source`'s permission bits.
    Raises: `<not-found>` or `<io-fail>`.
*/
void Path.copy_file(Path source, Path target) {
  File input = $auto(File.open(source, "rb"));
  File output = $auto(File.open(target, "wb"));
  input.copy_to(output, NULL);
  if (output.flush()) _path_error("Path.copy_file", target, errno);
  struct stat info = _stat("Path.copy_file", source);
  if (chmod(target, info.st_mode & 07777))
    _path_error("Path.copy_file", target, errno);
}

/** Copies `source` to `target`: a directory recursively, a symbolic link as
    a link, and a regular file with `Path.copy_file`.
    Raises: `<not-found>` or `<io-fail>`.
*/
void Path.copy_tree(Path source, Path target) {
  struct stat info;
  if (lstat(source, &info)) _path_error("Path.copy_tree", source, errno);
  if (S_ISLNK(info.st_mode)) {
    char buffer[PATH_MAX];
    ssize_t length = readlink(source, buffer, sizeof(buffer) - 1);
    if (length < 0) _path_error("Path.copy_tree", source, errno);
    buffer[length] = 0;
    if (symlink(buffer, target))
      _path_error("Path.copy_tree", target, errno);
  }
  else if (S_ISDIR(info.st_mode)) {
    target.make_dirs();
    foreach (String name, source.list_dir())
      source.join(name).copy_tree(target.join(name));
    if (chmod(target, info.st_mode & 07777))
      _path_error("Path.copy_tree", target, errno);
  }
  else source.copy_file(target);
}

/** Moves `source` to `target`, copying and removing when they are on
    different filesystems.
    Raises: `<not-found>` or `<io-fail>`.
*/
void Path.move_to(Path source, Path target) {
  if (!rename(source, target)) return;
  if (errno != EXDEV) _path_error("Path.move_to", source, errno);
  source.copy_tree(target);
  source.remove_tree();
}

/** Creates the symbolic link `link` pointing at `target`.
    Raises: `<io-fail>` when the link cannot be created.
*/
void Path.symlink_to(Path link, Path target) {
  if (symlink(target, link)) _path_error("Path.symlink_to", link, errno);
}

/** Returns the contents of the file at `path`, or NULL when it is empty.
    Raises: `<not-found>`, `<io-fail>`, or `<bad-arg>` when the file contains
    a NUL byte.
*/
String Path.read_text(Path path) =>
  File.open(path, "r").string_close();

/** Replaces the contents of the file at `path` with `text`.
    Raises: `<not-found>` when the directory does not exist, or `<io-fail>`.
*/
void Path.write_text(Path path, String text) {
  File output = $auto(File.open(path, "w"));
  output.write_all(text, text.len());
  if (output.flush()) _path_error("Path.write_text", path, errno);
}

/** Creates a new private directory under `TMPDIR`, or `/tmp`, and returns
    its path. The caller removes it, usually with `Path.remove_tree`.
    Raises: `<io-fail>` when the directory cannot be created.
*/
Path Path.temp_dir(void) {
  const char *parent = getenv("TMPDIR");
  Path root = parent && *parent ? String.new(parent) : "/tmp";
  String pattern = root.join("x2c-XXXXXX");
  char buffer[PATH_MAX];
  if (pattern.len() >= sizeof(buffer))
    _path_error("Path.temp_dir", root, ENAMETOOLONG);
  strcpy(buffer, pattern);
  if (!mkdtemp(buffer)) _path_error("Path.temp_dir", root, errno);
  return String.new(buffer);
}
