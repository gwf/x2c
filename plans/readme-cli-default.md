> Status: active
> Approved by Gary: simplify first-run documentation and default translation
> output to the current directory, retaining build's existing a.out default.

# First-run commands

Lead README with make build-safe and ./x2c run examples/foreach.x. Preserve
Gary's removal of log redirection. Keep a short build example and move manual
C compilation into the book; link to existing self-hosting documentation.

Baseline probes: build with no output option succeeds and creates a.out;
run succeeds without an output option; translate without --out-dir exits 2.
The top-level x2c link is already tracked. With the change, omitted output
uses the current directory and an explicit directory keeps its behavior.

Set the default once at translation entry, remove the mandatory-option error
and later fallback, and update help and its fixture. The existing CLI probe
now compares generated C/H from implicit and explicit output directories and
checks the default depfile and that no output appears beside the source.
The updated CLI probe passed, including existing explicit-directory cases.

Before publication, review the authored diff, then run agent-pr-check, which
owns bootstrap regeneration and final validation. Preserve the separate local
extension-publication commit. Do not move the already published release tag.

## Plan review

Translation entry supplies one output directory before existing preflight and
emission consume it. Existing directory and stem checks remain; no new check,
negative fixture, helper, representation, or traversal is added. This removes
the missing-option diagnostic and reuses the existing output path. The change
is a direct default assignment and deletion, with no language semantics beyond
the approved CLI default. Source review removes the now-redundant verbose
output null check. Build and run behavior remain unchanged.
