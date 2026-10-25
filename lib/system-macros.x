/*  system-macros.x -- convenience macros for text, timing, and processes

    Include this module to use its declarations.
*/

#pragma once
#include "meta.x"

/* Dedents the literal `text` was written as when its spelling is exact.
   Escaped, interpolated and computed values keep their meaning by calling
   String.dedent at run time. */
meta List _dedent_expand(Source text) {
  String source = Code.source_text(text);
  int length = source.len(), open = 0;
  if (length >= 3 && source.startswith("%\""))
    open = 2;
  else if (length >= 2 && source.startswith("\""))
    open = 1;
  if (open == 0 || !source.endswith("\"") || "\\" in source ||
      "$" in source)
    return $!( $(text.assoc(<syntax>)).dedent() );
  String body = source.getslice(open, length - 1, 1);
  return $!String{ $(body.dedent()) };
}

/* Normalizes the indentation a block of text was written with. The literal
   is dedented during translation when its spelling carries no escape and no
   interpolation hole; every other form calls String.dedent at run time, so
   both spellings mean the same thing. */
macro Expression $dedent(Expr $text) => $_dedent_expand($text);

/* Reports how long the following statement took on stderr. The caller
   includes <time.h>. The stop clock and the report run from a `defer`, so
   they still run when the decorated statement is a function body that
   returns or a body a raise transfers out of. */
macro Decorator $time(Stmt $target, Literal $label) {
  {
    struct timespec started, stopped;
    clock_gettime(CLOCK_MONOTONIC, &started);
    defer {
      clock_gettime(CLOCK_MONOTONIC, &stopped);
      double elapsed =
        (stopped.tv_sec - started.tv_sec) * 1000.0 +
        (stopped.tv_nsec - started.tv_nsec) / 1000000.0;
      Stderr.printf("[time] %s %.3f ms\n", $label, elapsed);
    }
    $target
  }
}

meta List _macros_location(void) =>
  $!String{ $(x2c_invocation_file() + ":" + x2c_invocation_line().str()) };

meta List _macros_source(Source code) =>
  $!String{ $(Code.source_text(code)) };

/* Checks an invariant and reports the failing expression as it was written.
   Unlike C `assert` this transfers to a catch and is not compiled out. */
macro Stmt $assert(Expr $check) {
  {
    if (!($check)) {
      raise %(invariant
        (check $($_macros_source($check)))
        (at $($_macros_location())));
    }
  }
}
