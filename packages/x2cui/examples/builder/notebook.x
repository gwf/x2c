/*  notebook.x -- the tree the builder opens when given no file

    A notes window laid out after md-edit: a file toolbar with Save, a
    framed editor with a formatting toolbar and a status bar, and a line
    for the last result. md-edit's own editor is a component of its own
    package, so a textarea stands in for it, and labels stand in for its
    icons. Save sends `save`, which the window handles; the formatting
    buttons send messages nothing handles yet, for wiring in the builder.
*/

module String notebook = %"
  (column ((pad 20) (gap 12) (height fill)
           (on save (lambda () (def status \"Saved notes.md.\"))))
    (row ((gap 8) (align center))
      (heading () \"Notes\" 3)
      (spacer ())
      (button ((variant ghost) (size sm) (on-click (send save))) \"Save...\"))
    (separator ())
    (column ((border 1) (radius 8) (gap 0) (height fill))
      (row ((pad 8) (gap 2) (align center))
        (button ((variant ghost) (size sm) (on-click (send undo))) \"Undo\")
        (button ((variant ghost) (size sm) (on-click (send redo))) \"Redo\")
        (separator ())
        (button ((variant ghost) (size sm) (on-click (send heading))) \"H\")
        (button ((variant ghost) (size sm) (on-click (send bold))) \"B\")
        (button ((variant ghost) (size sm) (on-click (send italic))) \"I\")
        (button ((variant ghost) (size sm) (on-click (send strike))) \"S\")
        (button ((variant ghost) (size sm) (on-click (send code))) \"Code\")
        (button ((variant ghost) (size sm) (on-click (send link))) \"Link\")
        (separator ())
        (button ((variant ghost) (size sm) (on-click (send bullets))) \"List\")
        (button ((variant ghost) (size sm) (on-click (send numbers)))
          \"Numbered\")
        (button ((variant ghost) (size sm) (on-click (send tasks))) \"Tasks\")
        (spacer ())
        (segmented ((bind view)) \"view\" (\"Formatted\" \"Source\")))
      (separator ())
      (textarea ((bind doc) (height -1)) \"notes\")
      (separator ())
      (row ((pad 8) (gap 8) (align center))
        (muted () \"260 words\")
        (spacer ())
        (muted () \"Ln 1, Col 1\")))
    (text () (eval (ui-text status))))";

module String notebook_program = %"
  (def status \"\")
  (def view 0)
  (def doc (ui-text
    \"# A small notebook\\n\"
    \"\\n\"
    \"This is a working document for the builder. Select a part of\\n\"
    \"the window and change its spacing, alignment, size, or style.\\n\"
    \"\\n\"
    \"## A few things to try\\n\"
    \"\\n\"
    \"- Select the formatting toolbar and change its gap.\\n\"
    \"- Make the Save button primary.\\n\"
    \"- Wire Bold to a procedure, and press it in run mode.\\n\"))";
