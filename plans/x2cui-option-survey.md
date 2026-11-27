# Which options to show: a survey of CUI and x2cui programs

> Status: survey run 2026-11-27 at Gary's request, to decide how the
> tweak panel ([probe](x2cui-live-tweak-probe.md)) shows more than the
> options a call writes and less than every field. A proposal; nothing
> beyond the probe is built.

## Result

A short list per component, holding the options real programs set in at
least 10% of that component's calls, covers 91% of all option uses while
listing 187 of the 488 fields of the 58 components programs used. The
panel can show that list for every chosen node, set or not, and keep the
rest behind "All options".

| Options listed per component | Options listed | Share of uses covered |
| --- | --- | --- |
| set in at least 5% of calls | 210 of 488 | 97% |
| set in at least 10% of calls | 187 of 488 | 91% |
| set in at least 20% of calls | 164 of 488 | 84% |

## Corpus

Counted are the `name: value` options of x2c `ui.NAME(...)` calls and
the `.field = value` options of C `cui_NAME(ui, ...)` calls, by
component. Applications and galleries are counted apart, because a
gallery sets every option on purpose; the table uses applications only.

| Corpus | Files | Calls | Option uses |
| --- | --- | --- | --- |
| CUI's example applications (`examples/*.c` but the galleries) | 11 | 860 | 1,408 |
| x2c applications: md-edit and md_editor, network-explorer and network_ui, mandelbrot, theme-test, x2cui's todo, mail, orders, counter | 34 | 985 | 630 |
| CUI's galleries | 3 | 866 | 1,235 |
| x2cui's gallery and scenes | 48 | 1,771 | 2,526 |

The scripts, counts, and full report are in
`.context/tweak-probe/survey/`. The count reads calls by pattern, not by
parsing, so a few options inside nested calls may be missed.

## The most used components

Application calls, the number of fields in the component's option record,
and the options applications set, by the share of calls that set them.

| Component | Calls | Fields | Most set |
| --- | --- | --- | --- |
| text | 154 | 10 | size 66%, color 60%, font 33%, nowrap 31%, width 18% |
| row | 130 | 35 | gap 79%, align 64%, width 62%, pad_x 22%, wrap 15%, height 11% |
| column | 95 | 35 | width 91%, gap 80%, height 41%, pad 22%, bg 21% |
| button | 87 | 12 | variant 55%, size 53%, icon 26%, disabled 16% |
| box | 55 | 35 | width 82%, height 60%, dir 36%, bg 31%, align 22%, radius 20%, justify 15%, gap 11% |
| icon_button | 50 | 12 | tooltip 100%, size 44%, variant 14%, color 10% |
| menu_item | 34 | 7 | icon 91%, danger 12%, checked 12% |
| scroll | 22 | 8 | id 100%, gap 77%, fade_edges 55%, width 50%, height 50%, pad 36% |
| input | 22 | 15 | label 55%, width 41%, placeholder 36%, autofocus 32%, icon 18%, size 18% |
| card | 20 | 15 | gap 100%, width 40%, min_width 35%, pad 25% |
| menu | 7 | 5 | icon 100%, icon_only 86%, variant 86%, placement 71%, width 29% |

Boxes are the clearest case: a row, column, or box record has 35 fields;
programs set 16 to 20 of them, and 6 to 9 account for nearly all uses.

## Proposal for the panel

Each chosen node shows three tiers:

1. **Written.** The options the call writes, editable when they are
   literals or names, as now. Options written as expressions are listed
   read-only with their source text, so the panel shows where a value
   comes from.
2. **Common.** The component's options set in at least 10% of calls,
   shown even when unset, as "default". Setting one inserts `name:
   value` into the call when written back. While tweaking, the form
   passes each unset common option through a tweak call that returns
   the field's zero, which CUI already reads as its default, so nothing
   changes until a value is set.
3. **All.** Every other field of the record behind "All options" with a
   search field, as the builder's inspector has.

The common list is data: one row per component and option, generated
from this survey and kept with x2cui. It replaces the builder's
hand-written `shown` table and answers open question 3 of the builder
redesign (where the option table lives): in x2cui, beside the forms
that read it.

## What this needs beyond the probe

- Write-back that inserts an option into a call, not only replaces one.
- Tweak calls for unset common options, generated from the table.
- Editors for sizes (`fill`, `fit`, a number), icons, and text, which
  the probe does not yet edit.
- A decision whether the common list is a fixed survey result or is
  recounted when the corpus grows.
