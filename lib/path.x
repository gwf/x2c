/*  path.x -- filesystem operations on path `String`s

    Copyright (c) 2026 Gary William Flake

    Paths stay ordinary `String`s; these methods read and change the files
    they name. A failure raises `<not-found>` when a named path does not
    exist and `<io-fail>` for any other host failure, both with `operation`,
    `path`, and `errno` details. Removing a path that is already absent
    succeeds.

    The path-part methods only examine text. `dirname` and `basename` follow
    POSIX, ignoring trailing slashes. Glob patterns use `*` and `?` within
    one path component, `[...]` character classes, `**` for any number of
    components, and backslash to quote the next character. Wildcards also
    match names that begin with a dot.
*/

#pragma once
#include "x2c.x"

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

static int _trimmed_length(String path) {
  int length = path.len();
  while (length > 1 && path[length - 1] == '/') length--;
  return length;
}

/** Returns `name` joined to `base` with one separating slash.
    An absolute `name`, or an empty `base`, is returned unchanged.
*/
String String.join_path(String base, String name) {
  if (!name) return base;
  if (!base || name[0] == '/') return name;
  return base.endswith("/") ? %"$base$name" : %"$base/$name";
}

/** Returns the directory part of `path`: `.` when it has no slash and `/`
    for a path directly under the root.
*/
String String.dirname(String path) {
  String trimmed = path[:_trimmed_length(path)];
  int slash = trimmed.rfind("/");
  if (slash < 0) return ".";
  while (slash > 0 && trimmed[slash - 1] == '/') slash--;
  return slash ? trimmed[:slash] : %"/";
}

/** Returns the last component of `path`, ignoring trailing slashes. */
String String.basename(String path) {
  String trimmed = path[:_trimmed_length(path)];
  if (trimmed == "/") return trimmed;
  int slash = trimmed.rfind("/");
  return slash < 0 ? trimmed : trimmed[slash + 1:];
}

/** Returns the extension of `path`'s last component, including its dot, or
    NULL when there is none. A leading dot does not start an extension.
*/
String String.extension(String path) {
  String base = path.basename();
  int dot = base.rfind(".");
  return dot > 0 ? base[dot:] : NULL;
}

/** Returns `path`'s last component without its extension. */
String String.stem(String path) {
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
String String.absolute_path(String path) {
  char buffer[PATH_MAX];
  if (realpath(path, buffer)) return String.new(buffer);
  if (!path.startswith("/")) {
    if (!getcwd(buffer, sizeof(buffer)))
      _path_error("String.absolute_path", path, errno);
    path = String.new(buffer).join_path(path);
  }
  String result = "/";
  foreach (String part, path.split("/")) {
    if (!part || part == ".") continue;
    if (part == "..") {
      result = result.dirname();
      continue;
    }
    result = result.join_path(part);
    if (realpath(result, buffer)) result = String.new(buffer);
  }
  return result;
}

/** Reports whether `path` names an existing file, following links. */
int String.exists(String path) {
  struct stat info;
  return path && stat(path, &info) == 0;
}

/** Reports whether `path` names a directory, following links. */
int String.is_dir(String path) {
  struct stat info;
  return path && stat(path, &info) == 0 && S_ISDIR(info.st_mode);
}

/** Reports whether `path` names a regular file, following links. */
int String.is_file(String path) {
  struct stat info;
  return path && stat(path, &info) == 0 && S_ISREG(info.st_mode);
}

static struct stat _stat(const char *operation, String path) {
  struct stat info;
  if (stat(path, &info)) _path_error(operation, path, errno);
  return info;
}

/** Returns the size of the file at `path` in bytes.
    Raises: `<not-found>` or `<io-fail>`.
*/
long String.file_size(String path) =>
  (long) _stat("String.file_size", path).st_size;

/** Returns the modification time of `path` in seconds since the epoch.
    Raises: `<not-found>` or `<io-fail>`.
*/
long String.modified_time(String path) =>
  (long) _stat("String.modified_time", path).st_mtime;

/** Returns the names in the directory `path`, sorted, without `.` and `..`.
    Raises: `<not-found>` or `<io-fail>`.
*/
List String.list_dir(String path) {
  DIR *directory = opendir(path);
  if (!directory) _path_error("String.list_dir", path, errno);
  Array names = %[], struct dirent *entry;
  while ((entry = readdir(directory)))
    if (strcmp(entry->d_name, ".") && strcmp(entry->d_name, ".."))
      names.push(String.new(entry->d_name));
  closedir(directory);
  return names.sort().list_free();
}

static void _walk(String directory, int depth, Array paths) {
  foreach (String name, directory.list_dir()) {
    String child = directory.join_path(name), struct stat info;
    paths.push(child);
    if (depth != 1 && lstat(child, &info) == 0 && S_ISDIR(info.st_mode) &&
        access(child, R_OK | X_OK) == 0)
      _walk(child, depth - 1, paths);
  }
}

/** Returns every path below the directory `root`, parents before their
    contents and siblings sorted. Symbolic links to directories are listed
    but not followed, and a directory that cannot be read is listed without
    its contents.
    Raises: `<not-found>` or `<io-fail>`.
*/
List String.walk(String root) {
  Array paths = %[];
  _walk(root, -1, paths);
  return paths.list_free();
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

static int _glob_match(const char *pattern, const char *text) {
  if (!*pattern) return !*text;
  if (pattern[0] == '*' && pattern[1] == '*') {
    const char *rest = pattern + 2;
    int components = *rest == '/';
    while (components && rest[1] == '*' && rest[2] == '*' && rest[3] == '/')
      rest += 3;
    for (const char *ch = text;; ch++) {
      if ((!components || ch == text || ch[-1] == '/') &&
          _glob_match(rest + components, ch))
        return 1;
      if (!*ch) return 0;
    }
  }
  if (*pattern == '*') {
    pattern++;
    if (_glob_match(pattern, text)) return 1;
    return *text && *text != '/' && _glob_match(pattern - 1, text + 1);
  }
  if (*pattern == '?')
    return *text && *text != '/' &&
           _glob_match(pattern + 1, text + 1);
  if (*pattern == '[') {
    if (!*text || *text == '/') return 0;
    const char *rest = pattern + 1;
    int matched = _class_match(&rest, (unsigned char) *text);
    if (matched < 0) return *text == '[' && _glob_match(pattern + 1, text + 1);
    return matched && _glob_match(rest, text + 1);
  }
  if (*pattern == '\\' && pattern[1]) pattern++;
  return *pattern == *text && _glob_match(pattern + 1, text + 1);
}

/** Reports whether all of `path` matches the glob `pattern`. */
int String.glob_match(String pattern, String path) =>
  pattern && path && _glob_match(pattern, path);

/** Returns the existing paths that match the glob `pattern`, sorted.
    The walk starts at the longest leading directory without a wildcard and
    descends only as deep as the pattern can match. No match returns an
    empty `List`.
*/
List String.glob(String pattern) {
  if (!strpbrk(pattern, "*?[\\"))
    return pattern.exists() ? %($pattern) : NULL;
  List parts = pattern.split("/");
  String base = NULL;
  int depth = 0, recursive = 0;
  foreach (String part, parts) {
    if (depth || strpbrk(part ? part : "", "*?[\\")) {
      depth++;
      if (part == "**") recursive = 1;
    }
    else base = base ? base.join_path(part) : part ? part : %"/";
  }
  String root = base ? base : %".";
  Array paths = %[], matches = %[];
  if (root.is_dir()) _walk(root, recursive ? -1 : depth, paths);
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
void String.make_dirs(String path) {
  char buffer[PATH_MAX];
  if (path.len() >= sizeof(buffer))
    _path_error("String.make_dirs", path, ENAMETOOLONG);
  strcpy(buffer, path);
  for (char *ch = buffer + 1; *ch; ch++) {
    if (*ch != '/') continue;
    *ch = 0;
    if (mkdir(buffer, 0777) && errno != EEXIST)
      _path_error("String.make_dirs", String.new(buffer), errno);
    *ch = '/';
  }
  if (mkdir(buffer, 0777) && errno != EEXIST)
    _path_error("String.make_dirs", path, errno);
  if (!path.is_dir()) _path_error("String.make_dirs", path, ENOTDIR);
}

/** Removes the file or symbolic link `path` when it exists.
    Raises: `<io-fail>` when it exists and cannot be removed.
*/
void String.remove_file(String path) {
  if (unlink(path) && errno != ENOENT)
    _path_error("String.remove_file", path, errno);
}

static void _remove_tree(String path, String *failed, int *failure) {
  struct stat info;
  if (lstat(path, &info)) {
    if (errno != ENOENT && !*failed) *failed = path, *failure = errno;
    return;
  }
  if (S_ISDIR(info.st_mode)) {
    DIR *directory = opendir(path);
    if (directory) {
      struct dirent *entry;
      while ((entry = readdir(directory)))
        if (strcmp(entry->d_name, ".") && strcmp(entry->d_name, ".."))
          _remove_tree(
            path.join_path(String.new(entry->d_name)), failed, failure);
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
void String.remove_tree(String path) {
  String failed = NULL;
  int failure = 0;
  _remove_tree(path, &failed, &failure);
  if (failed) raise %(io-fail (operation "String.remove_tree")
                      (path $failed) (errno $failure));
}

/** Copies the regular file `source` to `target`, replacing `target` and
    giving it `source`'s permission bits.
    Raises: `<not-found>` or `<io-fail>`.
*/
void String.copy_file(String source, String target) {
  File input = $auto(File.open(source, "rb"));
  File output = $auto(File.open(target, "wb"));
  input.copy_to(output, NULL);
  if (output.flush()) _path_error("String.copy_file", target, errno);
  struct stat info = _stat("String.copy_file", source);
  if (chmod(target, info.st_mode & 07777))
    _path_error("String.copy_file", target, errno);
}

/** Copies `source` to `target`: a directory recursively, a symbolic link as
    a link, and a regular file with `String.copy_file`.
    Raises: `<not-found>` or `<io-fail>`.
*/
void String.copy_tree(String source, String target) {
  struct stat info;
  if (lstat(source, &info)) _path_error("String.copy_tree", source, errno);
  if (S_ISLNK(info.st_mode)) {
    char buffer[PATH_MAX];
    ssize_t length = readlink(source, buffer, sizeof(buffer) - 1);
    if (length < 0) _path_error("String.copy_tree", source, errno);
    buffer[length] = 0;
    if (symlink(buffer, target))
      _path_error("String.copy_tree", target, errno);
  }
  else if (S_ISDIR(info.st_mode)) {
    target.make_dirs();
    foreach (String name, source.list_dir())
      source.join_path(name).copy_tree(target.join_path(name));
    if (chmod(target, info.st_mode & 07777))
      _path_error("String.copy_tree", target, errno);
  }
  else source.copy_file(target);
}

/** Moves `source` to `target`, copying and removing when they are on
    different filesystems.
    Raises: `<not-found>` or `<io-fail>`.
*/
void String.move_to(String source, String target) {
  if (!rename(source, target)) return;
  if (errno != EXDEV) _path_error("String.move_to", source, errno);
  source.copy_tree(target);
  source.remove_tree();
}

/** Creates the symbolic link `link` pointing at `target`.
    Raises: `<io-fail>` when the link cannot be created.
*/
void String.symlink_to(String link, String target) {
  if (symlink(target, link)) _path_error("String.symlink_to", link, errno);
}

/** Returns the contents of the file at `path`, or NULL when it is empty.
    Raises: `<not-found>`, `<io-fail>`, or `<bad-arg>` when the file contains
    a NUL byte.
*/
String String.read_text(String path) =>
  File.open(path, "r").string_close();

/** Replaces the contents of the file at `path` with `text`.
    Raises: `<not-found>` when the directory does not exist, or `<io-fail>`.
*/
void String.write_text(String path, String text) {
  File output = $auto(File.open(path, "w"));
  output.write_all(text, text.len());
  if (output.flush()) _path_error("String.write_text", path, errno);
}

/** Creates a new private directory under `TMPDIR`, or `/tmp`, and returns
    its path. The caller removes it, usually with `String.remove_tree`.
    Raises: `<io-fail>` when the directory cannot be created.
*/
String String.temp_dir(void) {
  const char *parent = getenv("TMPDIR");
  String root = parent && *parent ? String.new(parent) : %"/tmp";
  String pattern = root.join_path("x2c-XXXXXX");
  char buffer[PATH_MAX];
  if (pattern.len() >= sizeof(buffer))
    _path_error("String.temp_dir", root, ENAMETOOLONG);
  strcpy(buffer, pattern);
  if (!mkdtemp(buffer)) _path_error("String.temp_dir", root, errno);
  return String.new(buffer);
}
