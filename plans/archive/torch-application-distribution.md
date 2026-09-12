# Torch application relocation feasibility

> Status: done - bounded macOS feasibility probe completed 2026-09-11.
> Delivery commit subject: `overlap native fingerprints and close research probes`.
> No packaging interface or new supported-platform promise was added.

## Result

A current-source CPU application runs after moving its directory, using only
four private libtorch libraries and system frameworks/libraries. The existing
prepared prefix need not be modified. This establishes a practical macOS
relocation mechanism; it does not establish a signed, notarized, cross-platform
application distribution product.

The existing package bundle owner (`packages/tools/bundle.py`) distributes
source interfaces and archives with declared native inputs. Its documented
contract excludes shared-library relocation. A runnable executable directory
is a different output and should not silently replace that package contract.

## Reproduction and evidence

The input is the current-source tabular diagnostic application from the memory
investigation at 2befcb4, compiled against the prepared Torch 2.10.0 wheel on
arm64 macOS. Its additional allocator sampling is diagnostic only. Source,
probe scripts, native identity hashes, stdout/stderr and loader inspection are
retained under:

`/Users/gary/Documents/x2c-evidence/research-20260912/torch-application-distribution/`

The binary hashes are in the parent evidence directory. The probe copies the
application and the transitive non-system closure: `libtorch.dylib`,
`libtorch_cpu.dylib`, `libc10.dylib`, and `libomp.dylib`. It copies the prepared
wheel's LICENSE and NOTICE. These files and the executable occupy 218,955,228
bytes before adding the tabular data/checkpoint inputs.

Using the existing host `install_name_tool`, the probe rewrites dependencies
on the copies to `@executable_path/lib/...` in the executable and
`@loader_path/...` in libraries, removes their old rpaths, and updates library
IDs. Existing `codesign --sign -` restores ad-hoc signatures after mutation.
No original application, native prefix, host tool, or developer setting is
changed. The staged directory is renamed to `moved app with spaces` and run
from an unrelated working directory.

Original and relocated `check` runs both exit zero. All 19 scalar records and
64 training-curve observations match exactly. Four checkpoint artifacts are
produced by each run; resumed validation loss matches trained loss. This
compares reported CPU outcomes, not bytewise archive identity or a new Python
agreement measurement.

`DYLD_PRINT_LIBRARIES` confirms all four native libraries load from the moved
private directory and none from the original wheel prefix. Temporarily
removing the copied libc10 makes startup fail (signal 6) even though the
original prefix still exists. Restoring the copied library restores the
complete directory. This negative control proves the application does not
silently fall back to that prefix; the original prefix was never renamed or
hidden globally.

## Recommendation and remaining scope

Keep this mechanism as feasibility evidence until a real application target
selects supported platforms and delivery requirements. A production command
should reuse dependency metadata and identity/license receipts where possible,
but have an explicit application-directory output contract. It must establish
native dependency closure for the selected platform rather than copy this
macOS library list unconditionally.

Linux loader relocation, MPS execution, launch on a different macOS machine,
minimum-OS compatibility, signing/notarization and licensing completeness for
a distributable release were not established here. Ad-hoc signing is local
execution repair, not public distribution signing. These are release-scope
decisions, not prerequisites for the independent compiler improvement.
No generic packaging tool or new dependency is justified solely by this probe.

## Plan review

The native loader owns dependency resolution. Inspection, explicit relative
load names, execution tracing and the missing-private-library control verify
that boundary without a second dependency model in shipped code. Existing
application and native artifacts are copied, not mutated in place. No public
API, validation gate, runtime state, or source-package semantics change.
