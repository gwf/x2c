/*  source-files.x -- source files and dependencies */

/* The real paths this process has resolved, by spelling. The compiler never
   changes its working directory, and translation workers are forked processes,
   so successful resolutions are cached by spelling. An unresolved spelling is
   retried, because its file may appear later. */
static Map real_paths = NULL, static Scope real_paths_scope = NULL;

// source paths

/** Reads a source through the request view and retains exact response
    bytes.
*/
int Compiler.read_source(Compiler c, String path, String volatile &text) {
  if (!c.sources.read(path, text)) return 0;
  if (c.source_facts) c.source_texts[Path.absolute(path)] = text;
  return 1;
}

/** Reports whether an x2c source belongs to the current package root.
    Native headers and source outside that root keep their own names.
*/
int Compiler.owns_package_source(Compiler c, String path) {
  if (!c.package || !Path.is_x2c_source(path)) return 0;
  Var root = c.package_roots[c.package];
  return root is not void &&
    c.canonical_path(path).startswith(%"$(c.canonical_path(root))/");
}

/** Returns the canonical path of the source `file`. A relative name that
    is not a file resolves against the home.
*/
String Compiler.source_path(Compiler c, String file) {
  if (!file || file.startswith("<")) return file;
  String rooted = %"$(c.root_dir)/$file";
  if (file[0] != '/' && !c.sources.exists(file) && c.sources.exists(rooted))
    file = rooted;
  return c.canonical_path(file);
}

/** Returns the spelling that identifies the file at `path`. Through a
    source view it is the absolute path, because an unsaved file need not
    exist on disk; otherwise it is the real path, or `path` itself when that
    does not resolve.
*/
String Compiler.canonical_path(Compiler c, String path) {
  if (c.sources) return Path.absolute(path);
  String real = Path.real(path);
  return real ? real : path;
}

/** Returns `Path.absolute(path)`, resolving an existing file through
    `Path.real`.
*/
String Path.resolved_absolute(String path) {
  String real = Path.real(path);
  return real ? real : Path.absolute(path);
}

/** Returns the real path of the existing file at `path`, or NULL when
    `path` is NULL or does not resolve. Each spelling is resolved once per
    process.
*/
String Path.real(String path) {
  if (!path) return NULL;
  Var known = _real_paths()[path];
  if (known is <string>) return known;
  char resolved[PATH_MAX];
  if (!realpath(path, resolved)) return NULL;
  String real = resolved;
  if (path.try_own() && real.try_own()) real_paths[path] = real;
  return real;
}

/** Returns `path` relative to the canonical x2c home when it lies below the
    home, otherwise `path`. Interfaces, macro definitions, retained
    declarations, and generated identities spell paths this way, so they do
    not depend on where the home is installed.
*/
String Compiler.portable_path(String path) {
  String prefix = %"$(x2c_get_root())/";
  return path.startswith(prefix) ? path[prefix.len():] : path;
}

/** Returns the absolute path that a `Compiler.portable_path` spelling
    names.
*/
String Compiler.absolute_home_path(String spelling) =>
  spelling.startswith("/") ? spelling : %"$(x2c_get_root())/$spelling";

// translation dependencies

/** Records a path dependency not embedded in generated C. */
void Compiler.add_translation_dependency(Compiler c, String path) {
  c.deps.merge_translation_dependency(path, 1);
}

/** Merges another translation's dependency rows into this compiler. */
void Compiler.merge_translation_dependencies(Compiler c, Map dependencies) {
  foreach ((String path, Var content_hash) in dependencies)
    c.deps.merge_translation_dependency(path, content_hash);
}

/** Merges one translation dependency, preserving an existing content hash. */
void Map.merge_translation_dependency(Map m, String path, Var content_hash) {
  if (content_hash is <string>) {
    if (m[path] is not <string>) m[path] = content_hash;
  }
  else m.setdefault(path, 1);
}

// real path cache

static Map _real_paths(void) {
  if (real_paths != NULL) return real_paths;
  auto (&real_paths_scope) {
    Scope.shutdown_hook(_real_paths_shutdown);
    real_paths = {};
  }
  return real_paths;
}

static void _real_paths_shutdown(void) {
  real_paths_scope.destroy();
  real_paths_scope = NULL;
  real_paths = NULL;
}
