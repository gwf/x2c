/*  component-try.x -- try, catch, and finally

    A try lowers to the landing form `(landing CODE ROWS)` that the cleanup
    walk finishes: its frame, its finalizer as a region that leaves the
    frame on a transfer out of it, the exits that close its catch site,
    claim the finalizer, and leave the frame, then its body and each catch
    arm as regions that run those exits on every transfer out of them. The
    frame lands when something raises, and the catch site selects the arm.
    A clause's facts are
    `(HANDLE STATE (ARM...) PATTERN...)`: the handler the parser
    introduced, the catch site's initial state, the arms' tokens, and the
    patterns of the filtered arms, which precede the default arm.

    Each definition precedes the definitions that call it: the compiler
    settles whether a linked copy reaches a compile-time operation when the
    copy binds.
*/
#pragma once
#include "rewrite.x"
#include "grammar.x"

/* The linked meta copies include these diagnostics from this owner. */
macro Stmt $fail.try_finalizer_label(Expr $site, Expr $label) =>
  x2c_diagnostic_fail_at(
    $site, <emit>, "a finally body cannot define a label",
    %("a finalizer runs on every path that leaves its region, so '${
      Code.binding_spelling($label)}' would be defined once for each"));

// catch sites

/* Returns the statement that prepares each of `items` into its slot of
    the catch site's `patterns`; `$x2c.try.site` calls this in a slot. */
meta List _x2c_try_catch_patterns(List patterns, List items) {
  Array prepared = [];
  int index = 0;
  foreach (List pattern, items) {
    prepared.push($!{ $patterns[$index] = $pattern; });
    index++;
  }
  return prepared.list_free();
}

/* One catch site: its patterns prepared once, its handler pushed with
   them. */
macro Stmt $x2c.try.site(
  Name $frame, Name $handle, Expr $count, Expr $fallback, Expr $state,
  Expr @patterns) {
  static MatchCaptureSite arms[$count];
  Var patterns[$count];
  static ErrorCatchSite site = {arms, $fallback, $count, $state, -1};
  if (x2c_error_catch_site_pending(&site)) {
    @_x2c_try_catch_patterns(patterns, $patterns)
  }
  volatile ErrorHandler $handle =
    x2c_error_catch_site_push(&$frame, &site, patterns);
}

/* Returns the catch site `frame` pushes for the clause `clause`
    describes, or nothing for a try without one; `$x2c.try.frame` calls this in
    a slot. */
meta List _x2c_try_catch_site(List frame, List clause) {
  Macro site = $x2c.try.site;
  match (clause)
    case %(?handle ?(String state) ?(List arms) *patterns): {
      int count = arms.len(), filtered = patterns.len();
      String fallback = filtered < count ? filtered.str() : "-1";
      return site(
        frame, handle, count, %(expr (int) (literal (int) $fallback)),
        %(expr (int) $state), patterns);
    }
  return NULL;
}

// landings

/* Whether a lowered arm, a code value around its statement, returns or
   raises on every path out of it. */
meta static int _try_arm_exits(List arm) {
  match (arm) case %(code-value ? ?statement ?): {
    Code lowered = statement;
    return lowered.exits();
  }
  return 0;
}

/* Returns each lowered arm of `arms` chosen by its index in `selected`;
    `$x2c.try.handled` calls this in a slot. Each arm is its own
    statement, so a `break` or `continue` in it still reaches the enclosing
    loop, and only one test holds because `selected` does not change. When
    every arm returns or raises, control cannot leave them, and a final
    unreachable mark tells C so that a function ending in such a `try`
    needs no return after it. */
meta List _x2c_try_catch_cases(List selected, List arms) {
  Array cases = [];
  int index = 0, exits = 1;
  foreach (List arm, arms) {
    cases.push($!{ if ($selected == $index) $arm });
    index++;
    exits &= _try_arm_exits(arm);
  }
  if (exits) cases.push($!{ __builtin_unreachable(); });
  return cases.list_free();
}

/* A landing that hands a raised error to the arm its handler selected. */
macro Stmt $x2c.try.handled(
  Name $frame, Name $handle, Stmt $unhandled, Stmt @arms) {
  if (x2c_exception_is_error_target(&$frame)) {
    int selected = x2c_error_catch_selected($handle);
    x2c_error_catch_detach($handle);
    x2c_exception_mark_handled(&$frame);
    @_x2c_try_catch_cases(selected, $arms)
  }
  else $unhandled
}

/* Returns what runs when `frame` lands: the catch arm the clause's
    handler selected, or `exits` and no return; `$x2c.try.frame` calls this in
    a slot. A landing no catch arm handles runs the region's exits, and
    control does not come back. */
meta List _x2c_try_landing(List frame, List clause, List exits) {
  Macro landing = $x2c.try.handled;
  List otherwise = $!{ { $exits __builtin_unreachable(); } };
  match (clause)
    case %(?handle ? ?arms *):
      return landing(frame, handle, otherwise, arms);
  return otherwise;
}

// the frame

/* Places the lowered exits of a try after its regions, with the effect
    that marks the unit as needing exception support; `$x2c.try.frame` calls
    this in a slot. */
meta List _x2c_try_exits_placement(List exits) {
  Atom token = Atom.intern("?__try_cleanup");
  match (exits)
    case %(code-value ? ?statements ?):
      return Code.lowered(statements, %((cleanup $token $statements)));
  return NULL;
}

/* A try pushes its frame and lands on it when something raises. */
macro Stmt $x2c.try.frame(
  Name $frame, Expr $clause, Stmt $body, Stmt $exits) {
  {
    ExceptionFrame $frame;
    @_x2c_try_catch_site($frame, $clause)
    x2c_exception_push(&$frame);
    if (!sigsetjmp($frame.env, 0)) $body
    else {
      x2c_exception_landed(&$frame);
      @_x2c_try_landing($frame, $clause, $exits)
    }
    @_x2c_try_exits_placement($exits)
  }
}

// the lowering

/* The first label a finalizer defines, or NULL, with `at` the innermost
   position around it. A finalizer may nest as deeply as an expression
   chain is long, so the search keeps its pending work off the C stack. */
meta static Var _try_finalizer_label(Var value, List &at) {
  Array pending = [value], around = [at];
  Var found = NULL;
  while (!found && pending.len()) {
    Var current = pending.take_last();
    List here = around.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    match (node) {
      case %(function *): continue;
      case %(at ? ?wrapped): {
        pending.push(wrapped);
        around.push(node);
        continue;
      }
      case %(label ?name *): {
        found = name;
        at = here;
        continue;
      }
    }
    foreach (Var child, node) {
      pending.push(child);
      around.push(here);
    }
  }
  pending.free();
  around.free();
  return found;
}

/* Reports a label the finalizer defines: it runs on every path that
   leaves its region, so the label would be defined once for each. */
meta static void _try_check_label(List finalizer) {
  List at = finalizer;
  Var label = _try_finalizer_label(finalizer, at);
  if (!label) return;
  $fail.try_finalizer_label(at, label);
}

meta static List _try_frame_address(Atom frame) {
  Type type = %(("ExceptionFrame")), pointer = %(* ("ExceptionFrame"));
  return %(expr $pointer (op & (expr $type (ident $frame))));
}

/* A transfer out of a claimed finalizer leaves the frame as a handler
   that returns does: a pending error is discarded, and the frame is left
   without continuing its transfer. */
meta static List _try_departure(Atom frame) {
  List address = _try_frame_address(frame);
  return $!{
    x2c_exception_mark_handled($address);
    x2c_exception_leave($address);
  };
}

/* A catch closes before a claimed finalizer, then the frame leaves. */
meta static List _try_exits(Atom frame, List handle, Atom finalizer) {
  List before = NULL;
  if (handle) {
    List handler = %(expr (("ErrorHandler")) (ident $handle));
    List close = $!{ x2c_error_catch_close($handler); $handler = NULL; };
    before = %($close);
  }
  List address = _try_frame_address(frame);
  if (finalizer)
    return $!{
      if (x2c_exception_claim($address)) {
        @before
        $finalizer
      }
      x2c_exception_leave($address);
    };
  return $!{ @before x2c_exception_leave($address); };
}

/* The facts `$x2c.try.frame` writes a try's catch site and landing from, or
   NULL for a try without catches. Each arm is its own region, which a
   jump from the body may not enter, and leaves the try's exits. A pattern
   with a dynamic part is prepared again on each entry. */
meta static List _try_catch_clause(List handle, List records, Array rows) {
  if (!records) return NULL;
  String state = "ERROR_CATCH_PENDING";
  Array arms = [], patterns = [];
  foreach (List record, records) {
    Code pattern = record.car();
    if (pattern) {
      if (!pattern.is_static_pattern()) state = "ERROR_CATCH_TRANSIENT";
      patterns.push(pattern);
    }
    Atom arm = Atom.intern(%"?__try_arm_${arms.len()}");
    rows.push(%(region $arm ${record.cadr()}));
    arms.push(arm);
  }
  return %($handle $state ${arms.list_free()} @{patterns.list_free()});
}

/* The landing form of the try `node`: its frame, its finalizer in a
   region that leaves the frame, its exits, then its body and each arm
   inside them. */
meta static Code _try_landing(
  Code node, List body, List arms, List finalizer) {
  _try_check_label(finalizer);
  Atom frame = Atom.intern("?__exception_frame");
  Atom exits = Atom.intern("?__try_exits");
  Atom lowered = Atom.intern("?__try_body");
  Atom finished = NULL;
  List handle = arms ? source_catch_handle(node) : NULL;
  Array rows = [%(new-name $frame "exception_frame")];
  if (finalizer) {
    Atom departure = Atom.intern("?__try_departure");
    finished = Atom.intern("?__try_finalizer");
    rows.push(%(exits $departure ${_try_departure(frame)}));
    rows.push(%(region $finished $finalizer));
  }
  rows.push(%(exits $exits ${_try_exits(frame, handle, finished)}));
  rows.push(%(region $lowered $body));
  List clause = _try_catch_clause(handle, arms, rows);
  Macro shape = $x2c.try.frame;
  List code = shape(frame, clause, lowered, exits);
  return Code.lowered(%(landing $code ${rows.list_free()}), NULL);
}

$rewrite($caught)
$rewrite($tried)
/** Lowers the parsed try `node` to its landing form. */
meta Code try_lowering(Code node) {
  match (node) {
    case $caught(?body, ?finalizer, *arms):
      return _try_landing(node, body, arms, finalizer);
    case $tried(?body, ?finalizer):
      return _try_landing(node, body, NULL, finalizer);
  }
  return node;
}
