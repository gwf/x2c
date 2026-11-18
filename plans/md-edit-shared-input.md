# Shared focused-component input integration

> Status: implemented and verified locally, 2026-11-17. Submitted with the
> experimental CUI package branch; upstream integration owns publication.

## Delivered behavior

CUI owns focus eligibility, physical key bookkeeping, consumed-action masking,
and default fallback. A focused component owns its key map and commands. The
host routes declined events before CUI applies its defaults. Separately
committed text remains a separate event; consuming a key does not discard text.

The package applies `patches/component-input.patch` to its pinned experimental
CUI revision on native and WebAssembly builds. This is a package-carried CUI
change, not a claim that the upstream CUI project has released these APIs.

- `cui_set_input_hook` captures ordered, borrowed events before aggregation.
- `cui_dispatch_input` updates physical state, invokes the host route, then
  applies defaults only when appropriate. `cui_key_down` stays physical;
  `cui_key_action_down` excludes handled or inactive downs until release.
- `CUI_CANVAS_COMPONENT_INPUT` opts a canvas into component ownership without
  synthesizing Enter/Space button activation.
- `cui_request_component_focus` resolves an enabled participating target at
  frame completion. Missing, disabled and nonparticipating targets cannot
  acquire component focus. Removal revokes ownership.
- `cui_component_has_input`, `cui_focused_id`, `cui_window_focused` and
  `cui_input_repeated` expose the facts needed by component and host routing.
- `cui_draw_text_slanted` exposes the existing renderer operation required by
  md-edit, avoiding the editor's private CUI renderer patch.

x2cui exposes the raw API and ordinary `Ui` methods. `Ui.canvas_input` supplies
both participation flags. `Ui.dispatch_input` captures an x2c Error inside the
C callback and raises it after CUI returns. No Error unwinds CUI's dispatcher.

## md-edit adoption

The external application at `/Users/gary/Git/x2c-ux/md-edit` now uses the shared
package. Its build no longer copies or patches CUI. Its key resolver, commands,
Markdown prefix conversion, typed host requests and event queue remain local.
Capture callback Errors are raised after the native input pump returns.

The host preserves ordered replay. Dialog closure requests one conditional
reconciliation pass when necessary; shared CUI does not impose whole-UI replay.
The earlier prototype report contains the measured costs. This integration
adds no new timing claim and does not broaden the input contract to IME
composition, grapheme navigation or an accessibility text tree.

The external directory is not a Git repository. The 17 authored migration
files were applied after checking original source fingerprints. Previous
sources are retained in `.context/md-edit-before-shared-input` in the working
x2c checkout. Historical probe files remain unused by the new build.

## Verification

| Workload | Result |
| --- | --- |
| Shared package native unit tests | 39 tests, 180 assertions passed |
| Shared package native `check` | Passed; 232 rendered scenes, zero empty or unmatched components; refused literal checks passed |
| Shared package `web` | Gallery and stress browser artifacts built |
| Shared package `web-check` | 31 gallery pages rendered in Node/WebAssembly, zero empty |
| md-edit native model/component | 4261 model and 73 component checks passed |
| md-edit native input | 52 dispatch, 16 focus and 15 transition checks passed |
| md-edit native window | Hidden Cocoa ordering, navigation, scrolling, render and save checks passed |
| md-edit browser and Node builds | Built against the same shared package contract |
| md-edit Node/WebAssembly | Same model, component, dispatch, focus and transition suites passed |

The md-edit checks use explicit `X2C`, `PACKAGE_DIR`, `CUI_INCLUDE`,
`WASM_CUI_PREFIX`, `WASM_RUNTIME` and `WASM_PACKAGE` paths to the tested shared
checkout and dependency prefixes. They do not establish that a global installed
package was updated. Native screenshot rendering was inspected. Interactive
browser keyboard/IME testing was not performed in this integration pass.

Logs are `debug/component-package-{build,tests,check,web,web-check}.log` and
`/tmp/md-edit-shared-{native,web}.log`. The prior safe bootstrap remains in
`debug/bootstrap.log`; no compiler or bootstrap source changed in this work.

## Source review

The implementation reuses CUI's existing focus traversal and renderer. Focus
participation fits existing node padding and needs no component registry.
Opt-out callers retain legacy input behavior. md-edit deletes its private CUI
builder and probe policies instead of maintaining a second shared contract.

Raw and wrapper tests protect focus eligibility, handled/default separation,
physical release bookkeeping and the unsafe native callback boundary. The
client suites exercise command ownership, refusal fallback and dialog
transitions. These are focused submission checks, not new recurring gates.
