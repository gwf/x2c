/*  sourceview.x -- request-owned source overlays

    Copyright (c) 2026 Gary William Flake

    Logical paths keep their identity when an editor supplies unsaved text.
    Configure this view before opening a frontend unit; its immutable values
    and Map must outlive every compiler borrowing it.
*/

#pragma once

/** Owns configured immutable overlays in the request's active Context.
    A frontend and its units borrow this view. Text read from disk belongs
    to the reading unit, so the view never caches that shorter-lived text.
*/
typedef struct SourceView {
  Map overlays, dirty_paths;
} *SourceView;

#pragma private

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/** Creates a source view in the current request lifetime. */
SourceView SourceView.new(void) {
  SourceView sources = Scope.calloc(1, sizeof(struct SourceView));
  sources.overlays = %{};
  sources.dirty_paths = %{};
  return sources;
}

/** Resolves existing path components and normalizes missing final components.
    An unsaved new file therefore shares the identity of its real parent,
    including when that parent was reached through a symlink.
*/
String SourceView.path(String path) {
  char buffer[PATH_MAX];
  if (realpath(path, buffer)) return String.new(buffer);
  if (!path.startswith("/")) {
    if (!getcwd(buffer, sizeof(buffer))) return path;
    path = %"${String.new(buffer)}/$path";
  }
  String result = "/";
  foreach (String part, path.split("/")) {
    if (!part || part == ".") continue;
    if (part == "..") {
      int slash = result.rfind("/");
      result = slash > 0 ? result[:slash] : "/";
      continue;
    }
    result = result == "/" ? %"/$part" : %"$result/$part";
    if (realpath(result, buffer)) result = String.new(buffer);
  }
  return result;
}

/** Stores an immutable snapshot under its logical source path. Empty text
    is a present snapshot, not a request to fall back to the disk file.
*/
void SourceView.set(
  SourceView sources, String path, String text, int changed) {
  sources.overlays[SourceView.path(path)] = text;
  if (changed) sources.dirty_paths[SourceView.path(path)] = 1;
}

/** Returns whether this logical file has an unsaved overlay. */
int SourceView.is_changed(SourceView sources, String path) =>
  sources && sources.dirty_paths.contains(SourceView.path(path));

/** Returns readable-file presence, including unsaved new files. */
int SourceView.exists(SourceView sources, String path) {
  if (sources && sources.overlays.contains(SourceView.path(path))) return 1;
  struct stat info;
  return !access(path, R_OK) && !stat(path, &info) &&
         S_ISREG(info.st_mode);
}

/** Reads through the request overlay, falling back to a regular disk file.
    The return value distinguishes an empty file from a failed read. Disk
    text belongs to the calling unit; configured snapshots remain borrowed.
*/
int SourceView.read(
  SourceView sources, String path, String volatile *text) {
  Var value;
  if (sources && sources.overlays.try_get(SourceView.path(path), &value)) {
    *text = value.string();
    return 1;
  }
  struct stat info;
  File file = fopen(path, "r");
  if (!file) return 0;
  if (file.stat(&info) || !S_ISREG(info.st_mode)) {
    file.close();
    return 0;
  }
  try *text = file.string_close();
  catch %(io-fail *): return 0;
  return 1;
}
