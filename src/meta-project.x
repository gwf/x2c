/*  meta-project.x -- the project meta build

    Copyright (c) 2026 Gary William Flake.

    Before a translation starts, the bodied `meta` functions its inputs
    reach are compiled into one helper program linked against the runtime,
    which the translation then calls (`src/meta-helper-client.x`). They
    come from ordinary source units reached directly, by includes, or by
    packages. Meta code under the x2c root's `lib`, `src`, and `etc` is the
    compiler's own, linked into it.

    Each reached source unit gets its own table and native object.
    Public functions link between units; static helpers stay with their
    provider. The helper is cached under the x2c cache root,
    keyed by the SHA-256 of those sources, the compiler stamp, the C
    compiler's identity, and the flags, and is built again when a file its
    build read, x2c source or C header, changes.
*/

#pragma once
#include "frontend.x"

#include "cache.x"
#include "datum.x"
#include "digest.x"
#include "deps.x"
#include "meta-helper-client.x"
#include "module-schedule.x"
#include "json.x"
#include "script.x"
#include "toolchain.x"
#include "utils.x"
#include <unistd.h>

// helper table source

static macro Stmt $output.helper.header(Expr $out) {
  $out.write("#include \"x2c.h\"\n");
}

static macro Stmt $output.helper.target(Expr $out, Expr $index) {
  $out.printf("Map x2c_module_targets_%d(void);\n", $index);
}

static macro Stmt $output.helper.dispatch_begin(Expr $out) {
  $out.write("Map x2c_meta_helper_table(int index) {\n  switch (index) {\n");
}

static macro Stmt $output.helper.dispatch_case(Expr $out, Expr $index) {
  $out.printf(
    "    case %d: return x2c_module_targets_%d();\n", $index, $index);
}

static macro Stmt $output.helper.dispatch_end(Expr $out) {
  $out.write("  }\n  return NULL;\n}\n");
}

static macro Stmt $output.helper.count(Expr $out, Expr $count) {
  $out.printf("int x2c_meta_helper_count(void) { return %d; }\n", $count);
}

// preparing the helper

/* One project meta build. The Kth owner parses into table K.
   A build records the files it reads in `deps` and
   the result of each table in the fields after it. */
static typedef struct Helper {
  Frontend frontend, Array owners, Map packages;
  Toolchain toolchain, String include, identity, directory;
  List flags, Array modules;
  Map deps, before, readiness, prefix_compilers, publications, prefix_counts, header_active;
  Map native_sources, native_targets, native_loaded;
  Array groups, built, failures, objects, retained_dependencies, retained_tables;
  Array initializer_receipts;
  Scope lifetime;
  Compiler caller;
  int changed;
} Helper;

static Helper *active_helper = NULL;

/** Builds the helper that runs the project `meta` functions `inputs`
    reach, or finds it in the cache, and makes it the one their translation
    calls. Inputs that reach none use no helper. A group or helper that
    does not build is reported at the first call that needs it. */
void Frontend.prepare_meta(Frontend f, List inputs) {
  Helper h = {
    .frontend = f, .owners = [],
    .packages = {}, .deps = {}, .before = {}, .readiness = {},
    .prefix_compilers = {}, .publications = {}, .prefix_counts = {}, .header_active = {},
    .native_sources = {}, .native_targets = {}, .native_loaded = {},
    .groups = [], .built = [],
    .failures = [], .objects = [], .retained_dependencies = [],
    .retained_tables = [], .initializer_receipts = []};
  h.lifetime = Scope.owner(h.publications);
  h.scan(inputs);
  String include = NULL, cc = Compiler.meta_cc(include);
  String root = script_cache_root(), stamp = build_module_stamp();
  if (!h.owners.len() || !cc || !root || !stamp) {
    Compiler.use_meta_helper(NULL, NULL, NULL);
    return;
  }
  h.toolchain = toolchain_meta(cc);
  String compiler = Compiler.meta_cc_identity(cc);
  h.include = include;
  h.flags = _group_flags(f.request, h.packages);
  h.modules = _modules(f.request, h.packages);
  h.identity = h.identify(stamp, compiler);
  h.directory = _directory(root, h.identity, h.owners);
  h.use(h.manifest());
}

/* The manifest of the helper in the build directory: the one a previous
   build left while every file it read is unchanged, or a new build's. One
   process at a time does either, under the directory's lock. */
static List Helper.manifest(Helper &h) {
  Path.make_dirs(h.directory);
  int lock = file_lock(%"${h.directory}/lock", 1);
  defer close(lock);
  List manifest = _current(h.directory);
  if (manifest) return manifest;
  return h.build();
}

/* Each owner with a group calls its table, and a table or a helper that
   does not build keeps its reason for the first call that needs it. */
static void Helper.use(Helper &h, List manifest) {
  Map failures = {}, units = {}, groups = {};
  foreach (Var index, manifest.assoc(<groups>)) groups[index] = 1;
  foreach (List row, manifest.assoc(<failures>))
    failures[row.car()] = row.cadr();
  int index = 1;
  foreach (String owner, h.owners) {
    if (index in groups) units[owner] = index;
    index++;
  }
  String failure = manifest.assoc(<failure>);
  if (failure.len()) failures[-1] = failure;
  Compiler.use_meta_helper(
    failure.len() ? NULL : %"${h.directory}/helper", failures, units);
}

// reaching meta code

/* The scan of one input. `units` collects included meta providers;
   `seen` holds each file's result bits, and
   `packages` the root of each package imported. */
static typedef struct Scan {
  CliRequest request, Compiler c, Array units, Map seen, packages;
} Scan;

/* Each input or included file with meta code becomes an owner, so the
   constants it computes run in its own table when a unit collects it.
   Its path is canonical, as collection spells it. */
static void Helper.scan(Helper &h, List inputs) {
  Map owned = {};
  Compiler c = Compiler.new();
  c.sources = h.frontend.request.sources;
  c.include_dirs = h.frontend.include_dirs;
  foreach (String input, inputs) {
    String path = Path.absolute(input);
    Scan s = {
      .request = h.frontend.request, .c = c, .units = [], .seen = {},
      .packages = h.packages};
    int meta = s.file(path);
    if (!meta) continue;
    if (meta & 1) h.own(path, owned);
    foreach (String unit, s.units) h.own(unit, owned);
  }
  collect_forget_provisional_entries();
}

static void Helper.own(Helper &h, String path, Map owned) {
  if (path in owned) return;
  owned[path] = 1;
  h.owners.push(path);
}

/* Reads each file once. Bit 1 marks its own file-scope meta code; bit 2
   marks project meta code its includes or packages reach. An
   unfinished scan has neither bit, so cycles stop at their open file. */
static int Scan.file(Scan &s, String path) {
  Var found;
  if (s.seen.try_get(path, found)) return found;
  s.seen[path] = 0;
  if (_compiler_owns(path) && s.c.linked_meta_provider_current(path))
    return 0;
  String text = NULL;
  try text = Path.read_text(path);
  catch %((!or not-found io-fail) *): return 0;
  Tokenizer tokens = Tokenizer.new(text, <x2c>);
  tokens.layout = is_layout_file(path);
  tokens.scan();
  int meta = s.file_scope(tokens, Path.dirname(path));
  meta |= s.module_sources(path);
  if ((meta & 1) && _compiler_owns(path) &&
      (is_prelude_source(path) ||
       s.c.linked_meta_definitions_current(path))) meta &= ~1;
  s.seen[path] = meta;
  return meta;
}

/* Module providers share the project's native tables just as included
   providers do, including ordinary helpers reached by a meta body. */
static int Scan.module_sources(Scan &s, String path) {
  int meta = 0;
  foreach (String owner, s.c.module_tree.ancestors(path)) {
    s.units.push(owner);
    if (owner != path && s.file(owner)) meta = 2;
  }
  ModuleEntry entry = s.c.module_tree.entry(path);
  if (entry)
    foreach (String member, entry.members) {
      s.units.push(member);
      if (s.file(member)) meta = 2;
    }
  return meta;
}

/* Only file-scope tokens count. Each arm reads the tokens that follow its
   word. */
static int Scan.file_scope(Scan &s, Tokenizer tokens, String directory) {
  int depth = 0, meta = 0;
  for (Token token = tokens.next(); token.type != <eof>;
       token = tokens.next()) {
    String word = token.text;
    switch (token.type) {
      case <"{">: case <"%{">: case <"${">: case <"@{">:
        depth++;
        continue;
      case <"}">: depth--; continue;
    }
    if (depth) continue;
    if (word == "meta") meta |= _marker(token);
    else if (word == "import") meta |= s.package(tokens) ? 2 : 0;
    else if (token.type == <preproc>)
      meta |= s.include(word, directory) ? 2 : 0;
  }
  return meta;
}

/* Only a body or initializer needs a helper. Prototypes and protocol
   adoptions use their native supplier. In `meta native name(`, `native`
   is a type rather than the explicit native marker. */
static int _marker(Token token) {
  token = Token.skip_trivia(token + 1);
  if (token.text == "native") {
    Token name = Token.skip_trivia(token + 1);
    if (name.type == <eof> ||
        Token.skip_trivia(name + 1).type != <(>) return 0;
  }
  int depth = 0;
  for (; token.type != <eof>; token++) {
    Symbol kind = token.type;
    if (!depth) {
      if (kind == <;>) return 0;
      if (kind == <"{"> || kind == <"=>"> || kind == <"=">) return 1;
    }
    if (kind == <(> || kind == <[>) depth++;
    else if (kind == <)> || kind == <]>) depth--;
  }
  return 0;
}

/* A package entry is read as an ordinary source provider. */
static int Scan.package(Scan &s, Tokenizer tokens) {
  String name = _quoted(tokens.next()), root = NULL;
  String entry = name ? package_entry(
    s.request.sources, s.request.package_roots(), name, root) : NULL;
  if (!entry) return 0;
  s.packages[root] = 1;
  int meta = s.file(entry);
  s.units.push(absolute_path(entry));
  return !!meta;
}

/* An included source is read once; each meta provider joins `units`. */
static int Scan.include(Scan &s, String directive, String directory) {
  int angle = 0;
  String target = preproc_include_target(directive, angle);
  if (!target || !(target.endswith(".x") || target.endswith(".xp"))) return 0;
  String file = collect_resolve_include(
    s.request.sources, s.request.include_dirs, directory, target, angle);
  if (!file) return 0;
  String path = Path.absolute(file);
  int rooted = _compiler_owns(path);
  int meta = s.file(path);
  if (!rooted || (meta & 1)) s.units.push(absolute_path(path));
  return !!meta;
}

/* The text between a string token's quotes. */
static String _quoted(Token token) =>
  token.len >= 2 && token.text[0] == '"'
    ? String.new_len(token.text + 1, token.len - 2).unescape() : NULL;

static int _compiler_owns(String path) {
  String root = x2c_get_root();
  foreach (String directory, %("lib" "src" "etc"))
    if (path.startswith(%"$root/$directory/")) return 1;
  return 0;
}

// the cache key

/* A unit's group includes what the unit includes: the request's C
   directories and each imported package's headers. A package linked into
   the compiler uses the headers of its build. */
static List _group_flags(CliRequest request, Map packages) {
  List includes = request.include_dirs.map(%!(dir) => %("-I" $dir)).flatten();
  List flags = %(@includes @{_host_args(request.cc_args)});
  foreach (Var (root, _), packages)
    flags = %(@flags "-iquote" ${%"$root/builds"} "-iquote" ${%"$root/src"});
  String archive = Compiler.extension_archive();
  if (archive)
    flags = %("-iquote" ${%"${Path.dirname(archive)}/include"} @flags);
  return flags;
}

/* `cc_args` without the flags that select a target architecture, ABI, or
   system root, since the helper runs on the host. */
static List _host_args(List cc_args) {
  Array kept = [];
  for (List rest = cc_args; rest; rest = rest.cdr()) {
    String arg = rest.car();
    if (arg == "-target" || arg == "--target" || arg == "-arch" ||
        arg == "--sysroot" || arg == "-isysroot") {
      if (rest.cdr()) rest = rest.cdr();
    }
    else if (!arg.startswith("--target=") && !arg.startswith("--sysroot=") &&
             !arg.startswith("-m"))
      kept.push(arg);
  }
  return kept;
}

/* The request's native modules and the module of each imported package
   that the compiler does not link. */
static Array _modules(CliRequest request, Map packages) {
  Array modules = request.native_modules.map(
    %!(String path) => Path.absolute(path));
  foreach (Var (root, _), packages) {
    String name = Path.basename(root);
    String module = %"$root/builds/$name.module";
    if (!Compiler.links_extension(name) && Path.is_file(module) &&
        !(module in modules)) modules.push(module);
  }
  return modules;
}

/* Everything the helper is built with besides its sources. The helper's
   own source is read at build time, not linked into the compiler, so the
   stamp does not cover it. */
static String Helper.identify(Helper &h, String stamp, String compiler) {
  String loop = _loop_source();
  return %"$stamp\n$compiler\n${_cc_flags().repr()}\n"
    + %"${h.flags.repr()}\n${h.include}\n${h.toolchain.runtime_lib}\n"
    + %"${h.modules.list().repr()}\n"
    + %"${h.frontend.request.package_dirs.repr()}\n"
    + %"${h.packages.keys().list().sort().repr()}\n"
    + (Path.is_file(loop) ? Path.read_text(loop).sha256() : "");
}

/* The C compiler flags of meta code, besides its include directories. */
static List _cc_flags(void) => %("-fsigned-char" "-fPIC" "-O1");

/* Every helper links this unit, which answers the compiler's calls. */
static String _loop_source(void) => %"${x2c_get_root()}/etc/meta-helper.x";

/* The build directory is keyed by the identity and the paths of the
   sources. A changed source builds the same directory again, which keeps
   the helper when no group object changes. */
static String _directory(
  String root, String identity, Array owners) {
  Array key = [identity];
  foreach (String path, owners) key.push(path);
  return %"$root/meta/project-${String.sha256("\n".join(key))}";
}

// building the helper

/* Parses each owner into the group of its table, compiles the groups, and
   links the helper, keeping what an earlier build left when it is
   unchanged. The parses collect included files with placeholders for
   their meta calls, so translation collects those files again. Returns
   the manifest the build writes. */
static List Helper.build(Helper &h) {
  int count = h.owners.len() + 1;
  for (int index = 0; index < count; index++) {
    String base = h.base(index);
    h.before[index] = _digest(%"$base.o");
    _clear(base);
  }
  String loop = _loop_source();
  foreach (String path, %(@{h.owners} @{h.modules} $loop))
    h.deps[path] = 1;
  Compiler.use_meta_build_directory(h.directory, h.owners);
  defer Compiler.use_meta_build_directory(NULL, NULL);
  String failure = h.link(count);
  if (failure) return h.write_manifest(failure);
  Array tables = [];
  for (int index = 1; index < count; index++) tables.push(index);
  h.use(%((groups ${tables.list()}) (failures ()) (failure "")));
  Compiler.meta_helper_building(1);
  defer Compiler.meta_helper_building(0);
  defer Compiler.stop_meta_helper();
  $let(active_helper, &h) {
    int index = 1;
    foreach (String owner, h.owners) h.ready(owner, index++);
  }
  Compiler.stop_meta_helper();
  collect_forget_provisional_entries();
  return h.write_manifest(h.link(count));
}

/** Makes a project provider ready before publishing the value its call
    computes. Readiness follows calls actually reached by ordinary parsing. */
Var Compiler.prepare_meta_call(
  Compiler c, String name, Token site, List arguments, String provider) {
  if (!active_helper) raise %(meta-later (name $name));
  Helper *h = active_helper;
  $let(h->caller, c) {
    Var row;
    if (!provider.len() && c.project_meta.try_get(name, row))
      provider = ((List) row).cadr();
    String path = provider.len() ? real_path(home_absolute_path(provider))
                                : c.filename;
    int index = 1;
    foreach (String owner, h->owners) {
      if (owner == path) {
        Var state;
        if (h->readiness.try_get(owner, state) && state == 1) {
          String failure = (*h).prefix(owner, index, name);
          if (failure)
            c.report_error(<macro>, "native meta prerequisite cycle", site,
              %("provider: $owner" "function: $name" $failure));
          return c.meta_helper_call(name, site, arguments, owner);
        }
        String failure = (*h).ready(owner, index);
        if (failure) c.refuse_meta_call(name, site, failure);
        return c.meta_helper_call(name, site, arguments, owner);
      }
      index++;
    }
    c.refuse_meta_call(name, site, %"no project provider for $path");
  }
}

/** Records the active provider's ordinary-bound prefix for readiness calls. */
void Compiler.register_native_meta_prefix(Compiler c) {
  if (!active_helper || c.interface_provider) return;
  Helper *h = active_helper;
  String path = c.canonical_path(c.filename);
  foreach (String owner, h->owners)
    if (owner == path) {
      h->prefix_compilers[owner] = Var.new(<p48>, c);
      return;
    }
}

/** Supplies an ancestor interface without requiring unfinished native bodies. */
void Compiler.require_native_meta_header(Compiler c, String path) {
  if (!active_helper) return;
  Helper *h = active_helper;
  String owner = c.canonical_path(path);
  Var compiler;
  if (owner in h->header_active ||
      !h->prefix_compilers.try_get(owner, compiler)) return;
  int index = 1;
  foreach (String provider, h->owners) {
    if (provider == owner) {
      h->header_active[provider] = 1;
      defer h->header_active.del(provider);
      Var prior;
      int sequence = h->prefix_counts.try_get(index, prior) ? (int) prior + 1 : 1;
      h->prefix_counts[index] = sequence;
      Compiler prefix = compiler.pointer();
      $let(prefix.meta_build, index + 1)
        prefix.write_native_meta_header(sequence);
      return;
    }
    index++;
  }
}

static String Helper.prefix(Helper &h, String owner, int index, String name) {
  Var compiler;
  if (!h.prefix_compilers.try_get(owner, compiler))
    return "the defining body has not been bound";
  Compiler c = compiler.pointer();
  if (h.caller) {
    $let(c.diagnostics, h.caller.diagnostics)
      $let(c.diagnostics.printer, c) c.bind_native_meta_prefix();
  } else c.bind_native_meta_prefix();
  int found = 0;
  foreach (String target, c.native_prefix_definitions())
    if (target == name) found = 1;
  if (!found) return "the defining body depends on its unfinished prefix";
  Map published = h.publications[index];
  if (%(function $name) in published) return NULL;
  Var prior;
  int sequence = h.prefix_counts.try_get(index, prior) ? (int) prior + 1 : 1;
  h.prefix_counts[index] = sequence;
  String base = %"${h.base(index)}_prefix_$sequence";
  $let(c.meta_build, index + 1) c.write_native_meta_prefix(sequence, published);
  h.native_sources[index] = h.retain(base);
  h.native_targets[index] = h.retain(%"x2c_module_targets_${index}_prefix_$sequence");
  h.retained_tables.push(index);
  String failure = h.load_native_closure(index);
  if (failure) return failure;
  h.objects.push(h.retain(%"$base.o"));
  h.changed = 1;
  foreach (String function, c.native_prefix_functions())
    h.publish(published, %(function $function), 1);
  foreach (String value, c.native_prefix_values())
    h.publish(published, %(state $value), 1);
  foreach (List entry, c.meta_group)
    match (entry) {
      case %(function ? ?target *): h.publish(published, %(function $target), 1);
      case %(static (declare ? (bindings (op = (bind ?binding *) ?)))):
        h.publish(published, %(state ${binding_identity_spelling(binding)}), 1);
    }
  List resets = published.getdefault(%(initializers), %());
  h.publish(published, %(initializers),
    resets.append(%(${%"x2c_module_reset_${index}_prefix_$sequence"})));
  return NULL;
}

/* A completed provider is loaded once into the persistent build helper.
   Adding a table does not reset tables that have already answered calls. */
static String Helper.ready(Helper &h, String owner, int index) {
  Var state;
  if (h.readiness.try_get(owner, state)) {
    if (state == 2) return NULL;
    if (state == 3)
      foreach (List row, h.failures)
        if (row.car() == index) return row.cadr();
  }
  String failure = h.prepare_native(index);
  if (!failure) failure = h.load_native_closure(index);
  if (failure) {
    h.record(index, failure);
    h.readiness[owner] = 3;
    return failure;
  }
  return NULL;
}

/* Ordinary parsing publishes signatures and reached body edges once. */
static String Helper.prepare_native(Helper &h, int index) {
  String owner = h.owners[index - 1];
  Var state;
  if (h.readiness.try_get(owner, state)) {
    if (state == 1)
      return index in h.native_sources ? NULL
        : %"native meta prerequisite cycle: $owner has no available bound prefix";
    if (state == 2 || state == 4) return NULL;
    foreach (List row, h.failures)
      if (row.car() == index) return row.cadr();
  }
  h.readiness[owner] = 1;
  $scope(&h.lifetime) h.publications[index] = {};
  h.retained_tables.push(index);
  h.parse(owner, index);
  String base = h.base(index);
  if (Path.is_file(%"$base.failure")) return Path.read_text(%"$base.failure");
  h.native_sources[index] = h.retain(base);
  h.native_targets[index] = h.retain(%"x2c_module_targets_$index");
  h.retained_tables.push(index);
  h.readiness[owner] = 4;
  return NULL;
}

/* Runtime references differ from declaration and ordered producer edges. */
static String Helper.native_closure(
  Helper &h, int index, Map seen, Array providers, Map edges) {
  if (index in seen) return NULL;
  seen[index] = 1;
  String failure = h.prepare_native(index);
  if (failure) return failure;
  String owner = h.owners[index - 1], base = h.native_sources[index];
  providers.push(owner);
  Array prerequisites = [];
  String receipt = %"$base.native";
  if (Path.is_file(receipt))
    foreach (Var row, Json.parse(Path.read_text(receipt))) {
      int dependency = row.array()[0];
      String provider = h.owners[dependency - 1];
      String name = row.array()[1];
      if (h.readiness.getdefault(provider, 0) == 1 &&
          !(dependency in h.native_sources))
        failure = h.prefix(provider, dependency, name);
      else failure = h.prepare_native(dependency);
      if (failure) return failure;
      if (h.readiness[provider] == 1) {
        String available = %"${h.native_sources[dependency]}.available";
        if (!Path.is_file(available) ||
            !(name in Json.parse(Path.read_text(available)))) {
          failure = h.prefix(provider, dependency, name);
          if (failure)
            return %"native meta prerequisite cycle: $provider has no available definition of $name; $failure";
        }
      }
      if (!(provider in prerequisites)) prerequisites.push(provider);
      failure = h.native_closure(dependency, seen, providers, edges);
      if (failure) return failure;
    }
  edges[owner] = prerequisites.list_free();
  return NULL;
}

/* All selected initializer edges are checked before any component is loaded.
   Earlier loaded snapshots retain their receipts while their state survives.
   Every member of a runtime component links into one immediate-load object. */
static String Helper.load_native_closure(Helper &h, int index) {
  Array providers = [];
  Map edges = {};
  String failure = h.native_closure(index, {}, providers, edges);
  if (failure) return failure;
  foreach (String owner, providers) {
    int table = h.owners.find(owner) + 1;
    String base = h.native_sources[table];
    if (h.native_loaded.getdefault(table, "") == base) continue;
    failure = h.compile_files(base, owner);
    if (failure) return failure;
  }
  if (h.initializer_receipts.len()) {
    Compiler c = Compiler.new();
    c.own_diagnostics();
    c.check_native_initializer_receipts(h.initializer_receipts);
  }
  foreach (List component, declaration_work(providers.list_free(), edges)) {
    Array objects = [], targets = [], indices = [], identities = [];
    foreach (String owner, component) {
      int table = h.owners.find(owner) + 1;
      String base = h.native_sources[table];
      if (h.native_loaded.getdefault(table, "") == base) continue;
      objects.push(%"$base.o");
      targets.push(%($table ${h.native_targets[table]}));
      indices.push(table);
      identities.push(base);
    }
    if (!indices.len()) continue;
    String key = "\n".join(identities.list_free()).sha256();
    String module = %"${h.directory}/component-$key.module";
    List shape = %("-shared");
#ifdef __APPLE__
    shape = %("-bundle" "-undefined" "dynamic_lookup");
#endif
    failure = Compiler.meta_cc_run(
      %(${h.toolchain.cc} @shape @{objects.list_free()} "-o" $module), h.directory);
    if (!failure) failure = Compiler.load_meta_providers(module, targets.list_free());
    if (failure) return failure;
    foreach (int table, indices) {
      h.native_loaded[table] = h.native_sources[table];
      h.retained_tables.push(table);
      String owner = h.owners[table - 1];
      if (h.readiness[owner] == 4) {
        h.record(table, NULL);
        h.readiness[owner] = 2;
      }
    }
  }
  return NULL;
}

/* The path of table `index`'s group files, without their suffixes. */
static String Helper.base(Helper &h, int index) =>
  %"${h.directory}/group-$index";

/* Removes what a parse left of the group at `base`. */
static void _clear(String base) {
  foreach (String suffix, %(".c" ".xnm" ".native" ".available" ".deps" ".failure")) {
    String file = %"$base$suffix";
    if (Path.exists(file)) Path.remove_file(file);
  }
}

/* Parses the unit at `path` for the group of table `index`, which the
   parse writes into the build directory, adding the files it read to
   `deps`. Diagnostics are the translation's to report; a unit that does
   not parse leaves the part it reached, and the files it read decide when
   it parses again. */
static void Helper.parse(Helper &h, String path, int index) {
  Frontend f = h.frontend;
  $let(f.request.package_dirs, f.request.package_dirs) {
    foreach (Var (root, _), h.packages)
      f.request.package_dirs = f.request.package_dirs.append(
        %(${Path.dirname(root)}));
    h.parse_source(f, path, index);
  }
}

static void Helper.parse_source(
  Helper &h, Frontend f, String path, int index) {
  ParsedUnit unit;
  int dependencies = h.retained_dependencies.len();
  int tables = h.retained_tables.len();
  int failures = h.failures.len(), objects = h.objects.len();
  int started = f.start(path, unit);
  defer unit.close();
  defer h.export(unit.context, dependencies, failures, objects, tables);
  defer h.prefix_compilers.del(path);
  unit.compiler.meta_build = index + 1;
  Map previous = Compiler.use_native_meta_publications(h.publications[index]);
  defer Compiler.use_native_meta_publications(previous);
  unit.compiler.diagnostics.limit = 0;
  if (!started) return;
  if (!unit.collect(f) || !unit.parse()) {
    Path.write_text(%"${h.base(index)}.deps", path);
    Path.write_text(%"${h.base(index)}.failure",
      unit.compiler.diagnostics.entries().repr());
  }
  foreach (Var (read, _), unit.compiler.resolved_translation_dependencies())
    h.dependency(read);
}

/* Only records added during this provider can belong to its Context.
   Nested providers export into this one before it exports to its parent. */
static void Helper.export(
  Helper &h, Context context, int dependencies, int failures, int objects,
  int tables) {
  Map seen = {};
  for (int i = tables; i < (int) h.retained_tables.len(); i++) {
    int index = h.retained_tables[i];
    if (index in seen) continue;
    seen[index] = 1;
    if (index in h.publications) {
      Map publication = h.publications[index];
      publication = context.export(publication);
      Scope owner = Scope.owner(publication);
      publication.export_to(context, _export_native_record, &owner);
      h.publications[index] = publication;
    }
    foreach (Map retained, %(${h.native_sources} ${h.native_targets} ${h.native_loaded}))
      if (index in retained) retained[index] = context.export(retained[index]);
  }
  for (int i = failures; i < (int) h.failures.len(); i++)
    h.failures[i] = context.export(h.failures[i]);
  for (int i = objects; i < (int) h.objects.len(); i++)
    h.objects[i] = context.export(h.objects[i]);
  for (int i = dependencies; i < (int) h.retained_dependencies.len(); i++) {
    String previous = h.retained_dependencies[i];
    String retained = context.export(previous);
    h.deps.del(previous);
    h.deps[retained] = 1;
    h.retained_dependencies[i] = retained;
  }
}

static Var _export_native_record(Var value, Context context) =>
  context.export_nested(value);

/* Collection can call readiness inside its own temporary Context. */
static Var Helper.retain(Helper &h, Var value) {
  int retained = value is <list> ? value.list().try_own()
    : value is <string> ? value.string().try_own() : 1;
  if (!retained) raise %(bad-state (operation "native helper retention"));
  return value;
}

static void Helper.publish(Helper &h, Map publication, List key, Var value) {
  publication[h.retain(key)] = h.retain(value);
}

static void Helper.dependency(Helper &h, String path) {
  path = h.retain(path);
  if (path in h.deps) return;
  h.deps[path] = 1;
  h.retained_dependencies.push(path);
}

/* Compiles the group a parse left for table `index`, adding the headers it
   read to `deps`. A quoted include resolves from the directory of `unit`.
   Returns NULL when its object is built, or else why not. */
static String Helper.compile(Helper &h, int index, String unit) {
  return h.compile_files(h.base(index), unit);
}

static String Helper.compile_files(Helper &h, String base, String unit) {
  if (!Path.is_file(%"$base.deps")) return "the unit has no group";
  if (Path.is_file(%"$base.failure")) return Path.read_text(%"$base.failure");
  Toolchain t = h.toolchain;
  t.include_dir = h.include;
  t.cc_args = %(@{_cc_flags()} @{h.flags});
  List directories = %(${h.directory} ${Path.dirname(unit)});
  String projected, native_dependencies, errors;
  if (t.project_native_source(
      %"$base.c", directories, projected, native_dependencies, errors))
    return errors;
  if (native_dependencies) h.add_depfile(native_dependencies);
  String failure = Compiler.meta_cc_run(
    %(${t.cc} @{_cc_flags()} "-iquote" ${h.directory}
      "-iquote" ${Path.dirname(unit)} "-iquote" ${h.include} @{h.flags}
      "-MD" "-MF" ${%"$base.d"} "-c" $projected "-o" ${%"$base.o"}),
    h.directory);
  h.add_depfile(%"$base.d");
  if (!failure && native_dependencies) {
    String receipt = %"$base.xne";
    Path.write_text(receipt, Path.read_text(%"$projected.xne"));
    if (!(receipt in h.initializer_receipts))
      h.initializer_receipts.push(h.retain(receipt));
  }
  return failure;
}

/* Adds each dependency of the depfile at `path` to `deps`. */
static void Helper.add_depfile(Helper &h, String path) {
  if (!Path.is_file(path)) return;
  foreach (String dependency, translation_depfile_parse(Path.read_text(path)))
    h.dependency(Path.absolute(dependency));
}

/* A table whose parse left a group joins the groups, with why it does not
   build or with its object. An object that differs from the earlier
   build's changes the helper. */
static void Helper.record(Helper &h, int index, String failure) {
  String base = h.base(index);
  if (!Path.is_file(%"$base.deps")) return;
  h.groups.push(index);
  if (failure) h.failures.push(h.retain(%($index $failure)));
  else {
    h.built.push(index);
    h.objects.push(h.retain(%"$base.o"));
    if (_digest(%"$base.o") != h.before[index]) h.changed = 1;
  }
}

// linking

/* Links the helper with the runtime when an object or the table changed,
   so a change to program code alone keeps the helper. Returns why the
   helper does not link, or NULL. */
static String Helper.link(Helper &h, int count) {
  String failure = NULL;
  String support = h.support(failure);
  if (!support) return failure;
  String tables = %"${h.directory}/tables.c", table = _tables(h.built, count);
  String helper = %"${h.directory}/helper";
  if (!h.changed && Path.is_file(tables) && Path.read_text(tables) == table &&
      Path.is_file(helper)) return NULL;
  Path.write_text(tables, table);
  String output = _temporary(helper);
  failure = Compiler.meta_cc_run(
    h.link_arguments(output, tables, support), NULL);
  if (!failure) Path.move_to(output, helper);
  else if (Path.exists(helper)) Path.remove_file(helper);
  return failure;
}

/* The object of the helper's protocol loop, which this compiler translates
   once per identity, or NULL with `failure` set. */
static String Helper.support(Helper &h, String &failure) {
  String source = _loop_source();
  if (!Path.is_file(source)) {
    failure = %"cannot read $source";
    return NULL;
  }
  String key = String.sha256(
    %"${h.identity}\n${Path.read_text(source).sha256()}");
  String directory = %"${script_cache_root()}/meta/support-$key";
  String object = %"$directory/meta-helper.o";
  if (Path.is_file(object)) return object;
  Path.make_dirs(directory);
  int lock = file_lock(%"$directory/lock", 1);
  defer close(lock);
  if (Path.is_file(object)) return object;
  failure = h.compile_support(source, directory, object);
  return failure ? NULL : object;
}

/* Translates the loop's `source` into `directory` and compiles it to
   `object`. Returns why not, or NULL. */
static String Helper.compile_support(
  Helper &h, String source, String directory, String object) {
  String printed = NULL, errors = NULL;
  if (tool_capture(
    %(${x2c_get_executable()} "translate" "--out-dir" $directory $source),
    printed, errors))
    return %"cannot translate $source: ${errors.strip(NULL)}";
  Toolchain t = h.toolchain;
  String include = h.include, output = _temporary(object);
  String failure = Compiler.meta_cc_run(
    %(${t.cc} @{_cc_flags()} "-iquote" $directory "-iquote" $include
      "-c" ${%"$directory/meta-helper.c"} "-o" $output), NULL);
  if (!failure) Path.move_to(output, object);
  return failure;
}

/* The path a process writes before it moves the result to `path`. */
static String _temporary(String path) =>
  %"$path.${"%ld".printf((long) getpid())}";

/* The unit that gives the helper each built table by index. */
static String _tables(Array built, int count) {
  Buffer out = Buffer.new(0);
  $output.helper.header(out);
  foreach (int index, built)
    $output.helper.target(out, index);
  $output.helper.dispatch_begin(out);
  foreach (int index, built)
    $output.helper.dispatch_case(out, index);
  $output.helper.dispatch_end(out);
  $output.helper.count(out, count);
  return out;
}

/* Native modules use their host's runtime, including units the helper
   itself never calls, so the link matches the compiler's whole-runtime
   link. It also compiles the table, which includes the runtime headers. */
static List Helper.link_arguments(
  Helper &h, String output, String tables, String support) {
  Toolchain t = h.toolchain;
#ifdef __APPLE__
  t.ld_args = %(${%"-Wl,-force_load,${t.runtime_lib}"});
#else
  t.ld_args = %("-Wl,--export-dynamic,--whole-archive" ${t.runtime_lib}
                "-Wl,--no-whole-archive");
#endif
  List inputs = %(@{h.objects.list()} $tables $support);
  String archive = Compiler.extension_archive();
  if (archive) inputs = inputs.append(%($archive));
  ToolAction link = t.link_action(output, inputs);
  return %(@{link.arguments} @{_cc_flags()} "-iquote" ${h.include});
}

// manifests

/* Writes the manifest into the build directory and returns it:
   `(groups (K ...))` for each table that has a group, `(failures ((K WHY)
   ...))` for those that do not build, `(failure WHY)`, empty unless the
   helper does not link, and `(deps ((PATH DIGEST) ...))` for every file
   the build read. */
static List Helper.write_manifest(Helper &h, String failure) {
  List manifest = %(
    (groups ${h.groups.list()}) (failures ${h.failures.list()})
    (failure ${failure ? failure : ""}) (deps ${_digests(h.deps)}));
  Buffer out = $auto(Buffer.new(0));
  datum_write(out, manifest, 0);
  Path.write_text(%"${h.directory}/manifest", out);
  return manifest;
}

/* Each file of `paths` that can be read, with its digest, in order. */
static List _digests(Map paths) {
  Array rows = [];
  foreach (Var (path, _), paths) {
    String digest = _digest(path);
    if (digest) rows.push(%($path $digest));
  }
  return rows.sort();
}

/* The manifest a previous build left in `directory` when every file it
   read is unchanged, or NULL. */
static List _current(String directory) {
  String path = %"$directory/manifest";
  if (!Path.is_file(path)) return NULL;
  String text = Path.read_text(path);
  unsigned cursor = 0;
  Var datum = void;
  try datum_read(text, cursor, datum);
  catch %((!or incomplete malformed) *): return NULL;
  if (datum is not <list>) return NULL;
  List manifest = datum;
  /* A failure may come from a file the build could not read, such as a
     missing header, which no digest covers; build again. */
  if (manifest.assoc(<failures>) ||
      ((String) manifest.assoc(<failure>)).len())
    return NULL;
  foreach (List row, manifest.assoc(<deps>)) {
    (String file, String digest) = row;
    if (_digest(file) != digest) return NULL;
  }
  return manifest;
}

/* Hash readable contents and resolved identity; an absent candidate has a
   stable fact too, so adding it invalidates a cached helper. */
static String _digest(String path) {
  if (path.startswith("cwd:")) path = path[4:];
  if (!SourceView.exists(NULL, path)) return "search:absent";
  File input = fopen(path, "rb");
  if (!input) return NULL;
  defer input.close();
  return %"${Path.absolute(path)}:${input.sha256()}";
}
