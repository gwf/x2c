/*  modules.x -- native meta modules

    Copyright (c) 2026 Gary William Flake.
*/

/* The paths of the selected native modules that define `name`, in order. */
module List _native_module_suppliers(String name) =>
  native_module_order.filter(
    %!(String path) => name in ((Map) native_modules[path]));

/* native modules

   A native module is a shared library whose entry returns its targets.
   Loading runs its code inside the compiler, so a module loads only on
   request, once per process, and never unloads. */

/* Each loaded native module's name-to-`Func` Map by absolute path, and the
   paths the current request names, in its order. A module stays loaded for
   the process, so its Map lives in a Scope that lasts as long, while each
   request binds only the modules it names. */
module Map native_modules = NULL;
static List native_module_order = NULL;
module Scope native_module_scope = NULL;

/* The compiler supplies the operations `lib/meta.x` declares with a bodyless
   `meta` prototype, the `x2c_` targets, as the native module
   `compiler_supplier`, which every request selects first. */
static macro Expression $compiler.targets() => $(lisp.native.targets
  (filter lisp.compiler.target?
    (_x2c.native-meta.targets)));

static String compiler_supplier = "<compiler>";

static Map _compiler_targets(void) => $compiler.targets();

/** Returns the compiler's own targets, the operations `lib/meta.x` declares
    with a bodyless `meta` prototype, loaded as the native module every
    request selects first. */
Map Compiler.compiler_targets(void) {
  _load_compiler_module();
  return _compiler_targets();
}

static void _load_compiler_module(void) {
  if (!Compiler.native_module_loaded(compiler_supplier))
    Compiler.add_native_module(compiler_supplier, _compiler_targets);
}

/** Selects the loaded native modules, by absolute path, that bodyless `meta`
    prototypes bind in the current request. The first module in `paths`
    that defines a name supplies it.
*/
void Compiler.select_native_modules(List paths) {
  _load_compiler_module();
  Array linked = [];
  for (struct Extension *e = extensions; e; e = e.next) {
    String key = %"<${String.new(e.name)}>";
    if (!Compiler.native_module_loaded(key))
      Compiler.add_native_module(key, e.targets);
    linked.push(key);
  }
  paths = %($compiler_supplier @paths @{linked.list_free()});
  paths.try_own();
  native_module_order = paths;
}

/** Selects package `name`'s native module, when it has one, after the
    modules already selected, and records it as a prerequisite of the unit.
    The module is `<root>/builds/<name>.module`; a worker loads it itself
    when the process has not. A module from another compiler, or one on a
    platform that loads none, is reported at the import `token`.
*/
void Compiler.select_package_module(
  Compiler c, String name, String root, Token token) {
  String module = %"$root/builds/$name.module";
  if (Compiler.links_extension(name) || !Path.is_file(module)) return;
  if (!X2C_NATIVE_MODULES)
    $fail.meta_native_package_platform(c, token, name, module);
  c.add_translation_dependency(module);
  if (!Compiler.native_module_loaded(module))
    _load_package_module(c, name, module, token);
  if (module in native_module_order) return;
  $scope(&native_module_scope) {
    native_module_order = native_module_order.append(%($module));
    native_module_order.try_own();
  }
}

static void _load_package_module(
  Compiler c, String name, String module, Token token) {
  if (_module_stamp(module) != 1)
    $fail.meta_native_package_compiler(c, token, name, module);
  _open_native_module(module);
}

/** Loads the native module at `path` once per process and returns its
    absolute path. Loading runs the module's code inside the compiler, so it
    happens only on request. A module from another compiler, a file that is
    not a module, or an unsupported platform prints a diagnostic and exits.
*/
String Compiler.load_native_module(String path) {
  if (!X2C_NATIVE_MODULES)
    $fail.meta_native_module_platform();
  String absolute = Path.absolute(path);
  if (Compiler.native_module_loaded(absolute)) return absolute;
  int stamp = _module_stamp(path);
  if (stamp < 0) $fail.meta_native_module_invalid(path);
  if (!stamp)
    $fail.meta_native_module_compiler(path);
  _open_native_module(absolute);
  return absolute;
}

/** Loads the native module at absolute `path` when this compiler built it
    and the platform loads modules. A process that loads a module before it
    forks translation workers lets them inherit it; anything else is left
    for the import to report.
*/
void Compiler.preload_native_module(String path) {
  if (X2C_NATIVE_MODULES && !Compiler.native_module_loaded(path) &&
      _module_stamp(path) == 1)
    _open_native_module(path);
}

/* Reads the stamp in the bytes of the module at `path`. Loading runs a
   module's code, so a module from another compiler is rejected before it
   is loaded. */
static int _module_stamp(String path) {
  String expected = Compiler.module_stamp();
  if (!expected)
    $fail.meta_native_compiler_read(path);
  File input = fopen(path, "rb");
  if (!input)
    $fail.meta_native_module_read(path, String.new(strerror(errno)));
  fseek(input, 0, SEEK_END);
  long end = ftell(input);
  rewind(input);
  char *data = Scope.malloc(end > 0 ? (size_t) end : 1);
  size_t size = end > 0 ? fread(data, 1, (size_t) end, input) : 0;
  input.close();
  int stamp = _stamp_in(data, size, expected);
  Scope.free(data);
  return stamp;
}

/* 1 when the bytes hold one stamp and it names the running compiler, 0
   when it names another compiler or there is more than one, and -1 when
   they hold none. */
static int _stamp_in(char *data, size_t size, String expected) {
  String marker = "x2c-module-stamp:";
  int stamps = 0, current = 0, width = expected.len();
  for (size_t i = 0; i + marker.len() <= size; i++)
    if (!memcmp(data + i, marker, marker.len())) {
      stamps++;
      current = i + width <= size && !memcmp(data + i, expected, width);
    }
  return !stamps ? -1 : stamps == 1 && current;
}

/* Opens the module at absolute `path`, whose stamp was checked, and records
   its targets. Its constructors allocate its Funcs and literals in the
   module Scope, and it is never unloaded, because its Funcs borrow its
   code. */
static void _open_native_module(String path) {
  void *handle = NULL;
  $scope(&native_module_scope) handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!handle)
    $fail.meta_native_module_load(path, String.new(dlerror()));
  Map (*entry)(void) = (Map (*)(void)) dlsym(handle, "x2c_module_targets");
  if (!entry) $fail.meta_native_module_invalid(path);
  Compiler.add_native_module(path, entry);
}

/** Records the name-to-`Func` Map that the entry of the native module loaded
    from absolute `path` returns. The Funcs, names, signatures, and path last
    for the process.
*/
void Compiler.add_native_module(String path, Map (*entry)(void)) {
  Map targets = NULL;
  $scope(&native_module_scope) {
    if (!(void *) native_modules) {
      Scope.shutdown_hook(_native_module_shutdown);
      native_modules = {};
    }
    targets = entry();
    native_modules[path] = targets;
  }
  path.try_own();
  foreach (Var (name, target), targets) {
    name.string().try_own();
    ((Func) target.pointer()).signature().try_own();
  }
}

static void _native_module_shutdown(void) {
  native_module_scope.destroy();
  native_module_scope = NULL;
  native_modules = NULL;
  native_module_order = NULL;
}

/** Reports whether the native module at absolute `path` is loaded. */
int Compiler.native_module_loaded(String path) =>
  (void *) native_modules && path in native_modules;

/** Returns the name-to-`Func` Map of the loaded native module at absolute
    `path`. */
Map Compiler.native_module_targets(String path) => native_modules[path];

/** Reports whether the compiler itself supplies the native function `name`.
    Such a function exists only inside a compiler, so a `meta` function that
    reaches it has no runtime form.
*/
int Compiler.supplies_native_meta(String name) {
  Var targets;
  return (void *) native_modules &&
         native_modules.try_get(compiler_supplier, targets) &&
         name in ((Map) targets);
}

/* linked extensions

   The packages whose compile-time parts are linked into the compiler. Each
   registers from a constructor, before the runtime starts, so the list is
   plain C storage that lasts for the process. */

static struct Extension {
  const char *name;
  Map (*targets)(void);
  struct Extension *next;
} *extensions = NULL;

/** Registers package `name`'s compile-time part, linked into the compiler,
    whose `targets` returns its name-to-`Func` Map. The registration unit
    `x2c build --extension` generates calls it from a constructor.
*/
void x2c_register_extension(const char *name, Map (*targets)(void)) {
  struct Extension *extension = malloc(sizeof *extension);
  if (!extension) abort();
  *extension = (struct Extension) { name, targets, extensions };
  extensions = extension;
}

/** Reports whether package `name`'s compile-time part is linked into the
    compiler, so its import loads no module. */
int Compiler.links_extension(String name) {
  for (struct Extension *e = extensions; e; e = e.next)
    if (!strcmp(name, e.name)) return 1;
  return 0;
}

/** Returns the archive of the linked packages' objects that the build of
    this compiler kept beside it, named by the compiler's identity, or NULL
    when the compiler links none. Project meta code links it. */
String Compiler.extension_archive(void) =>
  extensions ? %"${x2c_get_executable()}.extensions/"
               + %"${Compiler.identity()}.a" : NULL;
