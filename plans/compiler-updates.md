# Compiler installation and updates

> Status: Implemented following authorization on 2026-11-15. Focused install,
> update, recovery, and release-assembly checks passed. Publication belongs to
> the shared integrator. Starting revision:
> `4a424f588e1011cc74e14141fedd6ae02b5ce1e3`.

## User-visible behavior

`make install` builds and installs the current checkout into
`$HOME/.local/x2c`. Repeating it updates that prefix without extra settings.
`PREFIX` and `DESTDIR` retain their explicit packaging meanings.
`make build-install` keeps its existing developer behavior: copy the compiler
to the checkout's branch-named binary and select it through `bin/x2c`.
Neither operation fetches Git changes or switches branches.

`x2c update --check` reports installed and available release versions without
changing files. `x2c update` installs a newer release into the installation of
the invoked compiler. An explicit `--version VERSION` selects a release,
including an intentional downgrade. Ordinary updates never downgrade.
`X2C_HOME`, the working directory, and another compiler on PATH do not select
the update destination. Source checkouts and source-installed compilers give
the corresponding `make install` instruction instead of downloading releases.

## Installation provenance

`.x2c-install-origin` records plain `key=value` lines; it is never shell code.
Source installation writes `kind=source`, `source=<absolute checkout>`, and
the payload identity. Release installation writes `kind=release`, its version,
release download base, version URL, and selected release tag. The receipt is
installation metadata outside the payload inventory's digest identity.
It is nevertheless owned by the installer and removed on uninstall.

Distribution staging writes no source receipt. The release installer writes
the receipt at the destination, so a release builder's source directory never
becomes the user's update source. Existing installations without a receipt
remain unknown; one source reinstall establishes source provenance, while
a release installer invocation with `--replace-origin` adopts an old release
installation.
Converting a recorded source installation to a release requires the release
installer's explicit `--replace-origin`. Source `make install` deliberately
selects source ownership of its destination.

## Owners and connected changes

- The Makefile owns the default prefix and existing developer target.
- `etc/x2c-payload.x` owns source receipts, distribution staging, and copying
  the installer into the payload as `etc/install.sh`.
- `site/public/install.sh` remains the one release download and replacement
  owner. It also implements the `--update` and `--check` operations.
- A shipped `commands/update` executable selects its actual installation and
  delegates to that installed script. The driver's update command lookup
  follows its executable rather than `X2C_HOME`; other commands keep their
  existing home selection.
- The installation guide, CLI reference, and build reference describe both
  workflows and their different ownership boundaries.

## Replacement and compatibility

Keep the existing staged download, checksum verification, and staged compiler
execution before replacement. Keep packages by moving them, without copying
potentially large native libraries. A sibling lock excludes concurrent
installers. Ordinary errors and handled signals restore the previous prefix;
an unhandled interruption leaves recoverable files and explicit recovery
instructions. This is not atomic for concurrent compilation: installation
requires an idle prefix. Do not add a version manager or a rollback command.

Release replacement refuses unrelated files outside `packages/`, naming the
conflict before mutation, instead of silently deleting or copying them.
Source installation retains its existing inventory-based preservation behavior.
Retained native packages with a different compiler version block release
replacement and receive remove/reinstall guidance. Source packages remain.
The update command does not silently migrate packages or change release feeds.

## Focused validation

Use scratch prefixes and inert release fixtures; never update the user's
personal prefix during tests. Verify bare `make install` with a scratch HOME,
explicit PREFIX/DESTDIR, source receipt refresh and removal, distribution
absence of source provenance, and installed command availability. Exercise
check-only, equal/newer/older versions, explicit version selection, source and
unknown refusal, recorded feeds, custom prefixes, X2C_HOME isolation, checksum
failure, unusable payloads, package compatibility, unowned-file refusal,
concurrency, and recoverable failed replacement. Extend existing command and
installer tests; do not add a recurring gate or change publication sequencing.

## Plan review

The existing payload inventory establishes owned paths. The compiler already
resolves its executable and command identity; update uses these owners rather
than inventing executable discovery. Existing release assembly establishes
archive identity, and the installer already verifies download checksums.
Those checks remain at their current boundaries. The new origin receipt
answers a fact the old inventory cannot establish: who installed the payload.

Reuse the shell installer and external-command framework. Remove the old
no-PREFIX branch of `make install`; retain `build-install` unchanged. The
command is an ordinary small x2c program, not another package manager.
The receipt, version comparison, and lock respectively prevent origin changes,
unintended downgrades, and overlapping mutations. No cache or global service
is introduced.

New diagnostics and negative fixtures protect deliberate public behavior:
unknown/source origins must not update from a release; invalid release
versions must not select arbitrary downloads; incompatible native packages
must not survive as apparently compatible bundles; unrelated files must not
be deleted; concurrent or interrupted replacements must not overwrite recovery
state. Existing checksum and executable checks continue protecting the old
working installation. Recovery remains bounded rather than adding a general
transaction framework.

## Implementation evidence

`make build-safe` and `make commands` passed. The source install probe passed
with the default prefix staged under a temporary DESTDIR, then verified source
update guidance, reinstallation, distribution staging without source origin,
and uninstall preserving personal files and packages.

The installed-command probe passed executable-based selection with conflicting
X2C_HOME, argument forwarding, backend status propagation, and checkout refusal.
The distribution smoke passed installation and compilation, package retention,
installed update execution with conflicting environment defaults, candidate
selection, unusable payload refusal, and checksum refusal.

Offline fixtures passed numeric version ordering, no-op updates without an
archive, read-only checking, deliberate downgrades, source/unknown refusal,
native bundle compatibility, unrelated-file refusal, lock exclusion, failed
replacement, TERM restoration, and SIGKILL recovery after package movement.
Seventeen release-candidate tests passed after adapting the installer template
substitution. Independent review identified and corrected the native bundle
version representation and multiline release-version handling.

The user's personal installation was not changed. No publication gate was run
in this submission worktree. The idle-prefix requirement still applies to
source installation, which does not participate in the release updater's lock.
Tests do not establish power-loss durability or every possible interruption
point; SIGKILL recovery uses the retained, explicit recovery script.
