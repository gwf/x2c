# x2cui live tweaking: probe

> Status: probe run 2026-11-27 on branch `x2cui-tweak-probe`, at Gary's
> request, to answer whether visual details of a finished program can be
> adjusted visually, in the program itself, and written back to source.
> Not a design decision; nothing here is on `dev` or `x2cui-builder`.

## Question

The builder edits a copy of a UI as a `View` tree. md-edit's toolbar uses
icons, painted glyphs, theme colours, computed sizes, and state, which a
tree cannot hold, and md-edit's look lives in its code. The probe tests
the other approach: instrument the running program, choose a box with the
pointer, change its literal options live, and write a value back to the
call in the source.

## Result

Every step worked on the real md-edit, built from a scratch copy against
this branch's compiler and x2cui. The original md-edit was not touched.

1. **Instrumented without editing md-edit's components.** x2cui's option
   lowering (`src/x2cui-options.x`) passes each numeric literal option of
   a form through `ui.tweak_value(file, line, column, name, value)`, and
   gives a box whose call names no id one made from its call site
   (`ui.tweak_id`). In md_editor that is 54 literal options and 25 boxes,
   with no change to md_editor's source.
2. **Chosen and changed live.** md-edit's draw function was wrapped in a
   stack with `ui.tweak_marks()` and beside `ui.tweak_panel()` (the
   patch is in `.context/tweak-probe/md-edit-main.patch`, 78 lines with
   the check). Choosing the toolbar row (`editor.x:1623`) listed
   `pad_left` 6, `pad_right` 18, and `gap` 2. Setting `pad_left` 40 and
   `gap` 14 moved the first divider from x 90 to x 148 on the next frame,
   the expected 34 + 24.
3. **Written back.** `gap` was written to the scratch `editor.x`; the call
   spans two lines and the change was `gap: 2` to `gap: 14` on line 1624.
4. **Round trip.** Rebuilt from the written source with no overrides, the
   divider started at x 114: 90 plus the 24 of the new gap.
5. **Cost.** 300 offscreen frames of md-edit: 2.2 to 2.4 ms CPU per frame
   with tweaking off and on alike, within run-to-run noise. Off, each
   literal is one call that returns its argument.

Pictures: `.context/tweak-probe/before-original.png` and
`after-override.png` (the row chosen, its literals in the panel).

## What the probe did not cover

- **Other kinds of value.** Of md_editor's 251 named options, 54 are
  numeric literals, which the probe edits. 147 are names such as
  `bg: surface`, `size: sm`, `variant: primary`, and `align: center`;
  each is an enum or theme member and could get a picker the same way.
  50 are expressions such as `e.split_toolbar ? 36 : 41`; they are shown
  as computed and stay code.
- **Components.** Only boxes are chosen. A button, an icon, or text has
  no record id; choosing one needs its id after the call (`last_id`).
- **Shared helpers.** A literal inside a helper such as `md_tool` is one
  call site for every tool it draws; the panel says how many were drawn
  from the call, and an edit changes them all, as editing the code would.
- **Structure.** Adding, removing, or moving components stays a code
  edit.
- **A window.** Selection by Alt and a click, and the panel, ran only
  off screen through the scripted hooks. md-edit's own input hook may
  take the click first in a window.
- **Identity.** While tweaking, a box gets a new id from its call site,
  which can change state CUI keys by id, such as a scroll position.
- **Overhead when built in.** Every x2cui program now carries the calls.
  A build option could leave them out.

## Code on the branch

- `packages/x2cui/src/x2cui-options.x`: `_tweaked` and the box id in
  `_initializers`, with the form's receiver held in `_tweak_receiver`
  while its record is built, and `_absolute` for the call site's path.
- `packages/x2cui/src/tweak/tweak.x`: the runtime, spliced into the main
  unit with a module block: recorded literals, overrides, boxes, the
  marks, the panel, write-back, and scripted hooks for the check.
- `make -C packages/x2cui check` passes with the probe built in.

## Answer to the question

Visual fine-tuning of a finished program is reachable this way: the
program draws itself, so icons, painted glyphs, and theme colours appear
exactly, and the values that are literals in the code can be changed and
saved. What remains is breadth (enum and theme pickers, components) and
a window test, not a new mechanism.
