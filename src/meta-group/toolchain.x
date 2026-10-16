/*  toolchain.x -- meta group toolchain

    Copyright (c) 2026 Gary William Flake.
*/

/** Selects the C compiler `cc` that builds the `meta` code of the units
    this process translates, with the runtime headers this compiler was
    built with, found from its installed headers in `include_dir`. */
void Compiler.use_meta_toolchain(String cc, String include_dir) {
  meta_cc = cc;
  meta_include_dir = _runtime_headers(include_dir);
  meta_cc.try_own();
  meta_include_dir.try_own();
}

/* The runtime headers this compiler was built with, which meta code shares
   because it calls the compiler's own runtime: a built checkout stage's
   `lib`, the checked-in bootstrap's, or else `include_dir`. */
static String _runtime_headers(String include_dir) {
  String stage = Compiler.stage_dir();
  if (stage && Path.is_file(%"$stage/lib/x2c.h")) return %"$stage/lib";
  String executable = x2c_get_executable(), root = x2c_get_root();
  if (executable && root && Path.basename(executable) == "x2c-bootstrap" &&
      Path.dirname(executable) == %"$root/bin")
    return %"$root/bootstrap/lib";
  return include_dir;
}

/** Returns the C compiler and the runtime header directory that build
    `meta` code, or NULL before `Compiler.use_meta_toolchain`. */
String Compiler.meta_cc(String &include_dir) {
  include_dir = meta_include_dir;
  return meta_cc;
}

/** Returns the identity of the C compiler at `cc`: its path and content
    hash. */
String Compiler.meta_cc_identity(String cc) {
  String path = "/" in cc ? cc : Env.find_program(cc);
  String hash = Path.content_identity(path);
  return hash ? %"$path $hash" : cc;
}

/** Runs `arguments`, a C compiler command building the group C in
    `directory`, and returns NULL, or else its first error, which names
    `directory` when a group's C is the cause. */
String Compiler.meta_cc_run(List arguments, String directory) {
  String printed = NULL, errors = NULL;
  if (!tool_capture(arguments, printed, errors)) return NULL;
  String failure = _cc_error(errors);
  return !directory || directory in failure ? failure
    : %"$failure; the group's C is in $directory";
}

/* The C compiler's first located error in `errors`, or else its first
   line, joined with the next when it ends in a colon, as a linker's
   undefined-symbol report does. */
static String _cc_error(String errors) {
  Array lines = [];
  foreach (String line, (errors ? errors : "").split("\n")) {
    String text = line.strip(NULL);
    if (!text) continue;
    if (": error: " in text && !text.startswith("clang:") &&
        !text.startswith("cc:") && !text.startswith("gcc:"))
      return text;
    lines.push(text);
  }
  if (!lines.len()) return "the C compiler failed";
  String first = lines[0];
  if (!first.endswith(":") || lines.len() < 2) return first;
  String next = lines[1];
  if (next.endswith(":")) next = next[:next.len() - 1];
  return %"$first $next";
}
