/*  sources.x -- source patterns, exclusions and deterministic ordering */

// command reports

static macro Stmt $progress.project_source_excluded(
  Expr $path, Expr $target) =>
  fprintf(
    stderr, "x2c: excluded %s from target %s\n", $path, $target);

// sources

/* What the source patterns match, less what the exclude patterns match,
   sorted. Every source is x2c or C. */
module Array _target_sources(Project p, ProjectTarget target) {
  if (!target.sources) _error_name(p, 0, "target has no sources", target.name);
  Array sources = _expand_patterns(p, target.sources, "source");
  Array excluded = _expand_patterns(p, target.exclude, "exclude");
  Array kept = [];
  foreach (String path in sources) {
    if (!(path in excluded)) kept.push(path);
    else if (p.command.verbose)
      $progress.project_source_excluded(path, target.name);
  }
  sources.free();
  excluded.free();
  kept.sort();
  foreach (String path in kept)
    if (!(Path.is_x2c_source(path) || path.endswith(".c")))
      _error_name(p, 0, "manifest source is not .x or .c", path);
  return kept;
}

/* The files the patterns match, each once, in the order they first match. */
static Array _expand_patterns(Project p, List patterns, String owner) {
  Array files = [];
  foreach (String pattern in patterns) {
    Array expanded = _expand_pattern(p, pattern, owner);
    foreach (String path in expanded) if (!(path in files)) files.push(path);
    expanded.free();
  }
  return files;
}

static Array _expand_pattern(Project p, String pattern, String owner) {
  Array matches =
    _has_glob(pattern) ? _glob(p, pattern) : _named_file(p, pattern);
  if (!matches.len())
    _error_name(p, 0, %"unmatched $owner pattern", pattern);
  return matches.sort();
}

static int _has_glob(String pattern) => pattern && strpbrk(pattern, "*?[");

/* A pattern with a wildcard matches the files, or the links to files, that
   its glob names below the project root, outside the build root, and the
   overlay files there too. */
static Array _glob(Project p, String pattern) {
  String prefix = p.root == "/" ? "/" : %"$(p.root)/";
  List found = Path.glob(Path.join(_glob_literal(p.root), pattern));
  if (p.sources) found = found.append(p.sources.overlays.keys());
  Array matches = [];
  foreach (String path in found)
    if (path.startswith(prefix) &&
        Path.glob_match(pattern, path.remove_prefix(prefix)) &&
        !(p.build_root && path.startswith(%"$(p.build_root)/")) &&
        p.sources.exists(path) && !(path in matches))
      matches.push(path);
  return matches;
}

/* `text` with its glob wildcards escaped, so a glob matches it literally. */
static String _glob_literal(String text) =>
  text.replace("\\", "\\\\").replace("*", "\\*").replace("?", "\\?")
    .replace("[", "\\[");

/* A pattern without a wildcard names one file. */
static Array _named_file(Project p, String pattern) {
  Array matches = [];
  String path = Path.join(p.root, pattern);
  if (p.sources.exists(path)) matches.push(path);
  return matches;
}
