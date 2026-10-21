# Source version viewer

A local source comparison tool with adjacent-version navigation, split and
unified diffs, token changes, change navigation, and line counts. It hides
comments in the displayed source. It has no external dependencies or network
services. Loaded source stays in the current browser tab.

## Open c2x2c

From the repository root:

```sh
python3 tools/version-viewer/refresh-snapshots.py
python3 -m http.server 8765 --bind 127.0.0.1 \
  --directory tools/version-viewer
```

Open <http://127.0.0.1:8765/?tutorial=ready>. Alternatively, open `index.html`
directly after generating snapshots. The latest comparison opens first.

The default manifest is `examples/c2x2c/versions.json`. Source files remain
under `examples/c2x2c`; the viewer contains no authoritative tutorial copies.
`snapshots.js` is a checked-in generated payload. `snapshots.json` is a local
generated export. Regenerate both after changing canonical source files.
Do not edit either payload. Generation does not compile or verify sources.

The generator adds a content hash to the snapshot script URL in `index.html`.
After regeneration, reload the page. If the browser caches the HTML itself,
append the printed hash to the page URL as `&v=HASH`. No browser storage needs
to be cleared.

## Compare another source sequence

Create a manifest. Each path is relative to the manifest's own directory:

```json
{
  "title": "Example revision sequence",
  "status": "Draft",
  "note": "Optional assumptions or context.",
  "versions": [
    {"label": "Version 0", "path": "before.c"},
    {"label": "Version 1", "path": "after.x"}
  ]
}
```

```sh
python3 tools/version-viewer/refresh-snapshots.py path/to/versions.json
```

This replaces the viewer's generated payload. Regenerate with the default
manifest to restore c2x2c. The generator locates its own files independently
of the current directory. It embeds source text, not workstation paths.

The UI can also load a JSON snapshot set or add pasted/uploaded source.
Snapshot JSON uses `filename` and `source` instead of manifest `path` fields.
The UI can export that set. Those edits last only in the tab unless exported;
they do not modify canonical repository files.
