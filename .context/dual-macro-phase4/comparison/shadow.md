# Comparable native-helper shadow evidence

The exact requested fixture is native-helper-shadow.x: caller-local int
x2c_exception_push=7 around try/finally. Both unchanged baseline and the
current bound/open control translate it, then fail native compilation with
called object type int is not a function or function pointer at the generated
x2c_exception_push call. Generated C is byte-identical (raw diff empty).
Both use the same absolute source path and explicit X2C_HOME pointing to
agent-dual-transport; hashes and build exits are in shadow-results.json.
This is pre-existing behavior/parity, not a regression from templates.
No scope-stack retention or hygiene repair was attempted.

The original phase3 open-shadow-fails.x is preserved and was rerun unchanged.
Both binaries BUILD it successfully. Both executable runs abort on calls==1
because this fixture expects an injected _compiler_open_target call absent
from both lowerings being compared. That original fixture does not establish
native shadow failure on the unchanged baseline. Its baseline build success
and callcount failure must remain distinct from the comparable native-helper
fixture above. Native build/run logs are retained beside this report.

Baseline SHA256 b0d9b1812930c7b7c9f38ab2c2347987510fa472060b3a88635a4055d9632c83
Current control SHA256 2b71c790cf8e0585a4e96ab4ffe098da7a689a17fde48eb9ea9fc610ce844b95

The complete phase4 slot/effect candidate is not this current control.
Full 62-case comparison and paired timings await its readiness.
