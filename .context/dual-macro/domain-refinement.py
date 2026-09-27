from pathlib import Path
p=Path('plans/dual-use-syntax-templates.md')
s=p.read_text()
s=s.replace('scope correspondence join Match\'s retry machinery.', 'scope correspondence join Match\'s retry machinery.')
s=s.replace('Neither has been implemented in the compiler by this spike.', '''Neither has been implemented in the compiler by this spike. A second concrete
integration question is the binding-domain bridge for templates compiled into
the native helper: helper-build IDs must never masquerade as program IDs.
Transparent skeletons plus a supplied current-domain environment are viable,
but that bridge has not been prototyped.''')
s=s.replace('Numeric identities remain unit/session-local. Helper calls for a unit can\ncarry them unchanged.', '''Numeric identities remain unit/session-local. Helper calls for a unit can
carry program syntax IDs unchanged. **Compiling the helper itself is a different
binding domain**: `src/meta-project.x:120-132` parses its units separately, and
`src/stage.x:758-772` borrows those build-compiler bindings. A cached native
helper therefore cannot embed its build-time IDs and use them to recognize
program references. Existing global `tpl-call` sidesteps that problem by
transporting a name for the active compiler to resolve.

Recommended transparent domain bridge:

- Compile a named getter or anonymous literal in a helper to a descriptor
  skeleton, indexed by owning source/declaration path and explicit external
  reference slots. Its body remains canonical syntax with the existing binding
  records; the descriptor's environment marks which records await rebinding.
  A lexical key selects an environment entry, not permission to construct ASTs.
- Ordinary program parsing registers the same literal/definition and resolves
  its definition-site references through existing binding operations. Send an
  inspectable map from skeleton keys/reference slots to current-domain binding
  records or complete descriptors with each applicable existing helper request.
  No nested callback is required. Local references need lexical registration;
  a global spelling fallback cannot resolve a local closure correctly.
- The helper hydrates a skeleton from that request environment before semantic
  recognition. A missing environment leaves an open descriptor inspectable,
  but cannot claim bound alpha matching or insert helper-build IDs as program
  references. Captured program syntax arguments already carry the correct
  program IDs. Name/member/type roles continue to use their own projections.
- Native helper locals are meta values, not program declarations. Capture such
  values by explicitly binding them into typed template holes; a List may carry
  program syntax and an integer may become a literal. Do not transport a C local
  variable's binding ID as a captured program reference. Anonymous literals
  formed directly in ordinary program lexical syntax capture that context's
  program references through its compiler-owned interface instead.

This bridge is proposed, not executed. An even smaller first experiment passes
an already hydrated template explicitly as a meta argument from the active
compiler, using the same data API. That proves dynamic construction/recognition
without proving getter/literal availability inside precompiled helper bodies.
The full implementation still includes those forms and their environment.''')
s=s.replace('static site contracts. Only after this evidence', 'static site contracts. Only after this evidence')
s=s.replace('carry values\n   through existing datum transport.', '''carry values
   through existing datum transport. Implement/probe the helper-build-to-program
   domain bridge: skeleton keys and external slots hydrate from current-domain
   template environments on existing requests. Do not cache hydrated local IDs
   across unit resets. Compare explicit template arguments as the smaller
   feasibility probe; it is not a substitute for the full getter/literal scope.''')
s=s.replace('Two output copies stay distinct', 'Two output copies stay distinct')
s=s.replace('- **Capture stage availability:**', '''- **Helper binding-domain bridge:** separate helper compilation is verified
  by source. Skeleton/environment hydration is a viable no-callback design but
  unprototyped; explicit compiler-origin template arguments are a simpler
  experiment. A bounded bridge probe must cover cached helper reuse across unit
  resets, named snapshot redefinition, local free references, anonymous literals
  and explicit meta-local value captures. Source/declaration keys and when to
  supply that environment remain implementation choices requiring evidence.
- **Capture stage availability:**''')
s=s.replace('Those are bounded next experiments with viable', 'Those and the helper domain bridge are bounded next experiments with viable')
s=s.replace('The largest unresolved cost is\nMatch retry integration, so it must be prototyped before production changes\nspread.', 'The largest unresolved costs are\nMatch retry integration and helper-domain hydration, so they must be prototyped\nbefore production changes spread.')
p.write_text(s)
