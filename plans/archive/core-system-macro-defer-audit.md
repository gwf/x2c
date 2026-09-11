# Every core defer: adoption audit

> Status: done
> Historical evidence archived with the compatible adoption, 2026-09-11.
> Complete per-statement review supporting core-system-macro-adoption.md.
> Baseline 8eb27f4bb2fad4d1ec179ed6fd9c1a3230b01a62, 2026-09-11.
> Historical source audit; implementation outcome is in the adoption plan.

## Result and method

**189 executable defer statements inspected individually: 81 src and 108
lib/templates.** Forty-five complete defer statements can become auto; one
additional Array cleanup inside a compound defer can become auto while its
state restoration stays. This gives 46 compatible managed locals. Each of
the other 143 statements has a concrete non-auto disposition below, including
eight paired Array defers requiring an error-cleanup decision.

Comments/literals were masked without changing offsets. Every remaining
`defer` token was reconciled against these rows: 17 additional src occurrences
are AST tags/patterns and one lib occurrence is scanner token recognition.
Templates are counted once, not per expansion. Generated lib/x2c.x is excluded.
The source rows use function names; the library rows include complete actions.
The [broader inventory](core-system-macro-inventory.md) resolves let/scope
alternatives and nondeferred cleanup; a non-auto disposition is not a claim
that no other simplification is possible.

## Complete src defer audit

Baseline 8eb27f4. All 81 executable defer statements in src/*.x were
inspected individually, including each block body and its acquisition/state
producer. The other 17 unquoted defer tokens are compiler AST tags/patterns,
not executable defer statements. src/ast-rewrite.xmacro has no defer.

A row is one written defer statement, even if it contains several actions.
Auto = compatible initialized local; Auto-mixed = one cleanup can be replaced
while other actions stay; Change = managed initialization changes acquisition
failure protection/order; Let/Mixed = state protocol, not resource cleanup;
Keep = retain the current owner/protocol.

| Source | Function | Disposition | Concrete reason |
| --- | --- | --- | --- |
| `src/ast.x:99` | ast_contains_head | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/build.x:865` | _build_remove_tree | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/cache.x:481` | _collect_cache_ids | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/collect.x:291` | _parse_segment | Keep | close_child needs parent plus child, moves diagnostics and unregisters Lisp; no one-value Cleanup. |
| `src/collect.x:473` | _file | Let | Restores declaration_effects, not allocation cleanup; full remainder is a let region. |
| `src/collect.x:721` | Compiler.collect_package | Keep | Parent-aware close_child retains final diagnostics before child Lisp teardown. |
| `src/compiler.x:852` | Compiler.run_declaration_effects | Mixed | Import-stack take_last plus filename restore; keep stack protocol; filename let must preserve take_last-before-restore and push-failure behavior. |
| `src/compiler.x:901` | _produce_declaration_rows | Let | Two saved fields macro_stack/source_private; no resource to auto-free. Preserve thaw timing and restoration ordering. |
| `src/compiler.x:932` | _select_declaration_rows | Let | Two saved fields macro_stack/source_private around default selection; keep case lifetime and continue exits. |
| `src/compiler.x:1006` | _select_declaration_forwards | Let | Saved source_private around forward selection; whole case can use let. |
| `src/compiler.x:1040` | Compiler.select_declaration_defaults | Keep | close_child depends on parent diagnostics; Compiler has no owning Cleanup adapter. |
| `src/compiler.x:1371` | Compiler.full_parse | Let | Restores recovery_depth after parsing; use let around existing block, no resource. |
| `src/compiler.x:1481` | _cache_literal_list | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/emit.x:258` | _runtime_static_value | Change | Both Arrays are acquired before either defer. Auto on both protects first on second acquisition failure; converting only the second reverses cleanup order; converting only the first preserves normal order but adds earlier failure cleanup. Separate error-cleanup policy choice. |
| `src/emit.x:259` | _runtime_static_value | Change | Both Arrays are acquired before either defer. Auto on both protects first on second acquisition failure; converting only the second reverses cleanup order; converting only the first preserves normal order but adds earlier failure cleanup. Separate error-cleanup policy choice. |
| `src/emit.x:386` | Emitter._collect_function_state | Change | Both Arrays are acquired before either defer. Auto on both protects first on second acquisition failure; converting only the second reverses cleanup order; converting only the first preserves normal order but adds earlier failure cleanup. Separate error-cleanup policy choice. |
| `src/emit.x:387` | Emitter._collect_function_state | Change | Both Arrays are acquired before either defer. Auto on both protects first on second acquisition failure; converting only the second reverses cleanup order; converting only the first preserves normal order but adds earlier failure cleanup. Separate error-cleanup policy choice. |
| `src/emit.x:591` | Emitter._block | Let | Snapshot native_aliases restored after mutations; let(place,place) possible, no allocation ownership. |
| `src/emit.x:1399` | Emitter._initializer_macro | Let | Temporarily disables compiler.source_map; preserve rendering boundary. |
| `src/emit.x:1420` | _source_type_definition | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/emit.x:1573` | Emitter._op_spine | Change | Both Arrays are acquired before either defer. Auto on both protects first on second acquisition failure; converting only the second reverses cleanup order; converting only the first preserves normal order but adds earlier failure cleanup. Separate error-cleanup policy choice. |
| `src/emit.x:1574` | Emitter._op_spine | Change | Both Arrays are acquired before either defer. Auto on both protects first on second acquisition failure; converting only the second reverses cleanup order; converting only the first preserves normal order but adds earlier failure cleanup. Separate error-cleanup policy choice. |
| `src/emit.x:1593` | Emitter._op_spine | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/emit.x:1612` | Emitter._emit | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/expressions.x:689` | _expression_requires_resolution | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/expressions.x:3014` | _initializer_conversion | Keep | Conditional completed/rejected rollback, diagnostic callback replay, array resize, emitter restoration and SymTxn rollback; auto cannot encode this transaction. |
| `src/generate.x:673` | _collect_forward_dependencies | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/lambda.x:169` | Compiler.lower_typed_adapter_expr | Let | Temporary c.origin around typed adapter case; preserve early returns. |
| `src/lambda.x:181` | Compiler.lower_typed_adapter_expr | Let | Temporary c.origin for remaining adapter body; whole body is eligible. |
| `src/lambda.x:992` | _collect_region_bindings | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/lambda.x:1054` | Compiler.check_lambda_captures | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/lambda.x:1087` | _collect_reference_captures | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/literals.x:999` | Compiler.capture_lambda_identifier | Let-change | Snapshot lambda_scopes after chain walk; snapshot let would move registration before walk. Keep traversal; evaluate separately. |
| `src/literals.x:1065` | Compiler.bind_lambda_expression | Keep | Symbol-table push/pop, not Scope allocation or an initialized Cleanup value. |
| `src/literals.x:1074` | Compiler.bind_lambda_expression | Let-change | begin_lambda_captures installs state; snapshot let must retain begin/end helpers and changes protection during begin. |
| `src/literals.x:1076` | Compiler.bind_lambda_expression | Keep | Second symbol scope for parameters; pop must follow binding/body lifetime, not free Sym. |
| `src/literals.x:1174` | Compiler.parse_lambda_literal | Let-change | Capture-frame restore after begin; preserve end captures and parameter-scope protocol. |
| `src/literals.x:1182` | Compiler.parse_lambda_literal | Let | Temporary return_type in compound lambda parsing; saved field, not owning local. |
| `src/macros.x:58` | _install_source | Keep | Parent-dependent Compiler.close_child; no matching one-value Cleanup contract. |
| `src/macros.x:516` | _eval_string | Let | Two global saved locations around eval try/catch; nested let, with original diagnostic context. |
| `src/macros.x:1073` | _import | Keep | Pops one import-stack element; must not free borrowed import_stack Array. |
| `src/macros.x:1091` | _import | Keep | Imported Compiler borrows maps/Lisp; parent-aware close_child retains diagnostics, not generic free. |
| `src/macros.x:1097` | _import | Let | set_emitter restores emitter and owner fields after borrowed diagnostics; retain order before close_child. |
| `src/macros.x:1172` | Compiler.evaluate_declaration_effect | Let | Restores collect_protocols over whole remainder; no Cleanup resource. |
| `src/macros.x:1330` | _eval_template_form | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/macros.x:1376` | _eval_template_form | Let | Six SDK globals; explicit restoration before report_error is also required. Capture message/notes outside lets and preserve reporting context. |
| `src/macros.x:1495` | _replace_definition_bindings | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/macros.x:2178` | Compiler.parse_macro_definition | Mixed | Symbol pop and three state restores; let conversion needs exact staggered starts and original pop-first order; auto cannot represent it. |
| `src/macros.x:2629` | Compiler.expand_macro_invocation_node | Keep | Conditional symbol-scope pop; no resource initializer, retain block_scope policy. |
| `src/macros.x:2632` | Compiler.expand_macro_invocation_node | Let | Temporarily installs invocation token; preserve outer symbol-pop ordering. |
| `src/macros.x:2671` | Compiler.expand_macro_invocation_node | Let | Snapshot macro_stack restored after delayed replacement; use snapshot let or retain defer if redundant assignment buys nothing. |
| `src/macros.x:2713` | Compiler.expand_macro_invocation_node | Let | Temporary expansion origin; ordinary saved field, not owning local. |
| `src/macros.x:2731` | _invoke_definition | Keep | SymTxn.rollback after optional commit; no Cleanup adoption. Preserve transaction protocol instead of inventing adapter. |
| `src/macros.x:2859` | _parse_target_definition | Keep | Same optional-commit SymTxn rollback; initialized value alone does not confer Cleanup. |
| `src/macros.x:2865` | _parse_target_definition | Keep | Conditional symbol-scope pop around target; paired parser scope, not memory Scope. |
| `src/macros.x:2932` | _parse_target_definition | Let | Temporarily restore invocation token only during transaction.commit; do not extend through return. |
| `src/main.x:125` | _compile_file | Keep | ParsedUnit is populated through frontend.start out-parameter; close takes pointer and handles staged ownership, not initialized Cleanup local. |
| `src/main.x:430` | _run_build_request | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/parse.x:426` | Compiler.parse_field | Let | aggregate_type during field macro parsing; compatible short let. |
| `src/parse.x:523` | Compiler.parse_enumerator | Let | aggregate_type during enumerator macro parsing; compatible short let. |
| `src/parse.x:1296` | _parse_expression_function_body | Keep | Symbol scope entered before expression body; no Cleanup value and no Scope relation. |
| `src/parse.x:1327` | _finish_function_parts | Mixed | Pop symbol scope then restore return_type/fn_name; lets can express fields but protect push failure earlier; retain exact cleanup ordering. |
| `src/parse.x:1548` | _finish_aggregate_type | Let-change | aggregate_type restore registered after bound allocation; moving to let changes allocation-failure restoration. |
| `src/parse.x:1617` | _finish_declarator_parameters | Keep | Per-fnmod parameter symbol scope; pop preserves parser binding ownership, not resource free. |
| `src/parse.x:1838` | Compiler.bind_syntax | Let | Temporary return_type across complete bind_syntax remainder; large body remains eligible. |
| `src/parse.x:1879` | Compiler.bind_syntax | Let | declaration_projection increment/decrement depth guard; potential let(depth,depth+1), verify recursive balance. |
| `src/parse.x:1922` | Compiler.bind_syntax | Let | Restores macro_stack after thawed recipe binding; preserve this case boundary. |
| `src/parse.x:2053` | Compiler.bind_syntax | Keep | Assigns params from sym.pop_scope return value; does not restore saved params or release allocation. |
| `src/parse.x:2157` | Compiler.bind_syntax | Keep | For-loop symbol scope; preserve parsing and binding sequence. |
| `src/parse.x:2186` | Compiler.bind_syntax | Keep | begin_catch_arm creates binding scope; pop after body, not a Cleanup handle. |
| `src/parse.x:2219` | Compiler.bind_syntax | Keep | begin_match_arm creates scope; guard/body use bindings through pop boundary. |
| `src/parse.x:2243` | Compiler.bind_syntax | Keep | Constructed block symbol scope; use existing Sym operation. |
| `src/protocol.x:2333` | _parse_protocol_member | Let | in_proto temporary flag while parsing declaration; no owning resource. |
| `src/statements.x:47` | _for_statement | Keep | For-statement symbol scope; replacing by auto would free wrong thing. |
| `src/statements.x:234` | _match_case | Auto-mixed | captures is local Array. Move its initializer into this same block as auto, keep field-restoration defer above its cleanup in unwind order; delete only captures.free from that defer. Can compose two lets. |
| `src/statements.x:468` | Compiler.parse_statement | Keep | Deletes binding fact and restores value OR absence of with-name key, then symbol pop; no stable addressable Map slot for let, no auto ownership. |
| `src/transform.x:1409` | _rewrite_defer_list | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/transform.x:1570` | _sequence | Auto | Existing adjacent initialized local and defer in same block; existing Cleanup delegates to this free/close. Keep binding and exit lifetime. |
| `src/transform.x:1628` | _op_chain | Change | Both Arrays are acquired before either defer. Auto on both protects first on second acquisition failure; converting only the second reverses cleanup order; converting only the first preserves normal order but adds earlier failure cleanup. Separate error-cleanup policy choice. |
| `src/transform.x:1629` | _op_chain | Change | Both Arrays are acquired before either defer. Auto on both protects first on second acquisition failure; converting only the second reverses cleanup order; converting only the first preserves normal order but adds earlier failure cleanup. Separate error-cleanup policy choice. |
| `src/transform.x:1694` | _node | Let | Temporarily sets anchored c.origin; keep occurrence for generated-origin bookkeeping. |

Counts: {'Auto': 17, 'Keep': 23, 'Let': 25, 'Mixed': 3, 'Change': 8, 'Let-change': 4, 'Auto-mixed': 1}.

Seventeen complete defers plus one free action in the mixed _match_case defer
are compatible auto changes (18 local owners). Eight additional Array owners
in four acquisition pairs need an explicit failure-cleanup decision. The
remaining defers are evaluated individually above, not silently discarded.

## Every hand-authored lib defer, individually reviewed

Excluded generated lib/x2c.x, comments/doc examples, string and symbol spellings. One row per defer statement; a compound cleanup body is one row. Templates count once before expansion. No production edits or migration execution.

Total **108 defer statements**, **28 confirmed $auto replacements**; the remaining statements each have an explicit disposition below.

| Source | Kind | Complete deferred action | $auto disposition |
|---|---|---|---|
| lib/array-generics.xmacro:248 | macro template | `defer if (copied) Block_free((Block) source);` | Reject auto: source aliases borrowed values unless self-overlap required copy; copied flag controls ownership. |
| lib/array-generics.xmacro:658 | macro template | `defer path.leave();` | Reject auto: RenderPath.leave removes active recursion path after successful enter; path is not an owning Cleanup resource. |
| lib/array-generics.xmacro:692 | macro template | `defer if ((void *) result == NULL) Block_free((Block) boxed);` | Reject direct auto: conditional rollback frees only unsuccessful staged/created value; success returns or publishes it. Preserve ownership flag and commit boundary. |
| lib/array-generics.xmacro:771 | macro template | `defer if ((void *) result == NULL) packed.free();` | Reject direct auto: conditional rollback frees only unsuccessful staged/created value; success returns or publishes it. Preserve ownership flag and commit boundary. |
| lib/array-generics.xmacro:804 | macro template | `defer if ((void *) staged != NULL && (void *) committed == NULL) staged.free();` | Reject direct auto: conditional rollback frees only unsuccessful staged/created value; success returns or publishes it. Preserve ownership flag and commit boundary. |
| lib/array.x:457 | authored function | `defer if ((void *) result == NULL) output.free();` | Reject direct auto: conditional rollback frees only unsuccessful staged/created value; success returns or publishes it. Preserve ownership flag and commit boundary. |
| lib/array.x:474 | authored function | `defer if ((void *) result == NULL) output.free();` | Reject direct auto: conditional rollback frees only unsuccessful staged/created value; success returns or publishes it. Preserve ownership flag and commit boundary. |
| lib/array.x:555 | authored function | `defer source.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/array.x:557 | authored function | `defer target.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/array.x:603 | authored function | `defer Scope.free(entries);` | Reject auto: native entry pointer has no Cleanup; preserve Scope.free of exact allocation. |
| lib/array.x:799 | authored function | `defer if ((void *) result == NULL) output.free();` | Reject direct auto: conditional rollback frees only unsuccessful staged/created value; success returns or publishes it. Preserve ownership flag and commit boundary. |
| lib/buffer.x:192 | authored function | `defer Scope.free(bytes);` | Reject auto: Scope-allocated char pointer has no owning Cleanup; representation change to Block is separate. |
| lib/buffer.x:338 | authored function | `defer buf.free();` | Reject auto: consuming Buffer parameter; initialized alias would merely add plumbing. |
| lib/context.x:117 | authored function | `defer if (!installed) { if (_.match_state) MatchCache.context_close(_.match_state); if (_.error_state) Error.context_close(_.error_state, x2c_exception_unwinding()); if (_.pool)     String.pool_release(); if (pushed)     Scope.pop(); if (_.scope)    Scope.destroy(_.scope); Scope.free(_); }` | Reject auto: conditional construction rollback closes match/error state, destroys Scope then record only on failed installation; successful Context escapes. |
| lib/context.x:240 | authored function | `defer if (!exported) Scope.move(array, &owner);` | Reject auto: conditional Scope.move restores allocation ownership on failed export; does not destroy the value. |
| lib/context.x:255 | authored function | `defer if (!exported) Scope.move(map, &owner);` | Reject auto: conditional Scope.move restores allocation ownership on failed export; does not destroy the value. |
| lib/dispatch.x:109 | authored function | `defer _descriptor_unlock();` | Reject auto/lock: descriptor native registry lock with dedicated initialization/abort policy, not Mutex. |
| lib/dispatch.x:126 | authored function | `defer _descriptor_unlock();` | Reject auto/lock: descriptor native registry lock with dedicated initialization/abort policy, not Mutex. |
| lib/dispatch.x:152 | authored function | `defer _descriptor_unlock();` | Reject auto/lock: descriptor native registry lock with dedicated initialization/abort policy, not Mutex. |
| lib/dispatch.x:190 | authored function | `defer _descriptor_unlock();` | Reject auto/lock: descriptor native registry lock with dedicated initialization/abort policy, not Mutex. |
| lib/error.x:1011 | authored function | `defer _region_destroy(&view);` | Reject auto: custom ErrorRegion address cleanup, existing zero-then-initialize boundary inside error dispatch; no Cleanup adapter. |
| lib/file.x:159 | authored function | `defer if (written) *written += offset;` | Reject auto: writes accepted byte count back to optional caller pointer; not resource cleanup or saved-value restoration. |
| lib/file.x:184 | authored function | `defer { if ((void *) first != NULL) first.free(); if ((void *) content != NULL) content.free(); }` | Reject auto: combined String then Block cleanup with NULL-disarming and transfer to canonical String; String lacks owning Cleanup; preserve order. |
| lib/file.x:226 | authored function | `defer file.close();` | Reject auto: consuming File parameter, not initialized owned local. Artificial alias adds code. |
| lib/file.x:388 | authored function | `defer if ((void *) owned != NULL) owned.free();` | Reject auto: owned alias becomes NULL after canonical transfer; String has no general owning Cleanup. |
| lib/file.x:414 | authored function | `defer funlockfile(file);` | Reject auto/lock: native FILE stream unlock; File Cleanup closes, Mutex lock contract differs. |
| lib/file.x:486 | authored function | `defer line.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/file.x:511 | authored function | `defer content.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/file.x:525 | authored function | `defer if (!keep) { line.free(); iter.state = void; }` | Reject auto: iterator Block survives successful pull/construction; conditional free and state clearing preserve transfer ownership. |
| lib/file.x:554 | authored function | `defer if (!keep) line.free();` | Reject auto: iterator Block survives successful pull/construction; conditional free and state clearing preserve transfer ownership. |
| lib/func.x:281 | authored function | `defer if (!result) Scope.free(fn);` | Reject auto: allocation rollback only when Func construction fails; successful handle escapes. |
| lib/lisp.x:427 | authored function | `defer Scope.pop();` | Reject auto; retain explicit pop: nested scope decorator eagerly evaluates the outer SDK capture before substitution. Execution corrected this staging assumption. |
| lib/lisp.x:443 | macro template | `defer Scope.pop();` | Reject auto; retain explicit pop: nested scope decorator eagerly evaluates the outer SDK capture before substitution. Execution corrected this staging assumption. |
| lib/lisp.x:457 | authored function | `defer if (!result) Scope.destroy(session);` | Reject auto: session construction failure-only destroy; successful session returned to caller. |
| lib/lisp.x:517 | authored function | `defer Scope.destroy(tokens_scope);` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/lisp.x:866 | authored function | `defer if (result is void) Scope.free(lambda);` | Reject auto: lambda allocation failure-only free; successful closure escapes; native record lacks Cleanup. |
| lib/lisp.x:899 | authored function | `defer Scope.destroy(frame);` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/lisp.x:902 | authored function | `defer Scope.pop();` | Reject auto; retain explicit pop: nested scope decorator eagerly evaluates the outer SDK capture before substitution. Execution corrected this staging assumption. |
| lib/lisp.x:1036 | authored function | `defer source.close();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/lisp.x:1274 | authored function | `defer l.depth--;` | Reject auto: depth decrement balances nesting count; possible let candidate requires preserving nested mutations, not owning cleanup. |
| lib/lisp.x:1315 | authored function | `defer Scope.pop();` | Reject auto; retain explicit pop: nested scope decorator eagerly evaluates the outer SDK capture before substitution. Execution corrected this staging assumption. |
| lib/lisp.x:1434 | authored function | `defer _machine_slot_release(lisp, slot);` | Reject auto: slot lease release needs both session and slot and ordered machine teardown; no standalone Cleanup contract. |
| lib/lisp.x:1444 | authored function | `defer m.running = 0;` | Reject auto: clears running flag ahead of slot finish; deliberately zero, not restore old value. |
| lib/lisp.x:1603 | authored function | `defer Scope.destroy(tokens_scope);` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/lisp.x:1630 | authored function | `defer content.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:324 | authored function | `defer values.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:343 | authored function | `defer lists.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:366 | authored function | `defer values.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:441 | authored function | `defer values.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:542 | authored function | `defer values.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:556 | authored function | `defer values.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:570 | authored function | `defer values.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:592 | authored function | `defer arr.free();` | Reject auto: consuming Array parameter, not initialized local. |
| lib/list.x:669 | authored function | `defer items.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:699 | authored function | `defer values.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:725 | authored function | `defer values.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:809 | authored function | `defer values.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:823 | authored function | `defer values.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:859 | authored function | `defer source.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:861 | authored function | `defer values.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:971 | authored function | `defer path.leave();` | Reject auto: RenderPath.leave removes active recursion path after successful enter; path is not an owning Cleanup resource. |
| lib/list.x:1015 | authored function | `defer path.leave();` | Reject auto: RenderPath.leave removes active recursion path after successful enter; path is not an owning Cleanup resource. |
| lib/list.x:1105 | authored function | `defer values.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/list.x:1121 | authored function | `defer values.free();` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/logger.x:144 | macro template | `defer _unlock();` | Reject auto/lock: private synchronized policy native lock, not Mutex lifetime or cleanup. |
| lib/logger.x:263 | authored function | `defer if (!result && destroy) destroy(data);` | Reject auto: invokes optional user destructor on failed ownership transfer; Var data has no Cleanup. |
| lib/logger.x:331 | authored function | `defer logger.emission_depth--;` | Reject auto: nesting/emission counter decrement, not resource cleanup; assess let separately against reentrant mutations. |
| lib/logger.x:455 | authored function | `defer if (pushed) Scope.pop();` | Reject auto: conditionally undo destination push; no acquired owned-local resource; scope rewrite must preserve conditional push policy. |
| lib/logger.x:457 | authored function | `defer if (!appended) added.free();` | Reject auto: Buffer transferred to persistent scratch array on successful append, freed only if append fails. |
| lib/logger.x:464 | authored function | `defer context.depth--;` | Reject auto: nesting/emission counter decrement, not resource cleanup; assess let separately against reentrant mutations. |
| lib/logger.x:494 | authored function | `defer if (!handed_off) _destroy_text(data);` | Reject auto: custom text sink destructor only until handoff; successful sink owns state. |
| lib/logger.x:504 | authored function | `defer if (pushed) Scope.pop();` | Reject auto: conditionally undo destination push; no acquired owned-local resource; scope rewrite must preserve conditional push policy. |
| lib/logger.x:547 | authored function | `defer Scope.pop();` | Reject auto; retain explicit pop: nested scope decorator eagerly evaluates the outer SDK capture before substitution. Execution corrected this staging assumption. |
| lib/logger.x:639 | authored function | `defer Scope.pop();` | Reject auto; retain explicit pop: nested scope decorator eagerly evaluates the outer SDK capture before substitution. Execution corrected this staging assumption. |
| lib/logger.x:711 | authored function | `defer logger.emission_depth--;` | Reject auto: nesting/emission counter decrement, not resource cleanup; assess let separately against reentrant mutations. |
| lib/map-generics.xmacro:132 | macro template | `defer Bytes_free(staged_hashes);` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/map-generics.xmacro:135 | macro template | `defer Bytes_free(staged_entries);` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/map-generics.xmacro:273 | macro template | `defer if ((void *) result == 0) copy._core_free();` | Reject direct auto: conditional rollback frees only unsuccessful staged/created value; success returns or publishes it. Preserve ownership flag and commit boundary. |
| lib/map-generics.xmacro:286 | macro template | `defer if (created && !result) map._core_free();` | Reject direct auto: conditional rollback frees only unsuccessful staged/created value; success returns or publishes it. Preserve ownership flag and commit boundary. |
| lib/map-generics.xmacro:580 | macro template | `defer Scope.destroy(scratch);` | CONFIRMED auto: initialized local and existing Cleanup match current defer; preserve block and final binding. See ownership ledger for boundary details. |
| lib/map-generics.xmacro:606 | macro template | `defer path.leave();` | Reject auto: RenderPath.leave removes active recursion path after successful enter; path is not an owning Cleanup resource. |
| lib/map-generics.xmacro:813 | macro template | `defer if ((void *) staged != 0 && (void *) committed == 0) staged._core_free();` | Reject direct auto: conditional rollback frees only unsuccessful staged/created value; success returns or publishes it. Preserve ownership flag and commit boundary. |
| lib/map.x:450 | authored function | `defer if (!rebuilt) rebuilt_hashes.free();` | Reject immediate auto: failure-only stage becomes installed map storage; individual initializer registration also changes second-acquisition failure behavior. |
| lib/map.x:451 | authored function | `defer if (!rebuilt) rebuilt_entries.free();` | Reject immediate auto: failure-only stage becomes installed map storage; individual initializer registration also changes second-acquisition failure behavior. |
| lib/match.x:1997 | authored function | `defer Scope.pop();` | Reject auto; retain explicit pop: nested scope decorator eagerly evaluates the outer SDK capture before substitution. Execution corrected this staging assumption. |
| lib/match.x:2334 | authored function | `defer Scope.pop();` | Reject auto; retain explicit pop: nested scope decorator eagerly evaluates the outer SDK capture before substitution. Execution corrected this staging assumption. |
| lib/match.x:2346 | authored function | `defer Scope.pop();` | Reject auto; retain explicit pop: nested scope decorator eagerly evaluates the outer SDK capture before substitution. Execution corrected this staging assumption. |
| lib/pool.x:460 | authored function | `defer if (!finished) { if (pushed) Scope.pop(); if (mutex_ready) pthread_mutex_destroy(&pool.mutex); Scope.destroy(scope); }` | Reject auto: partial constructor rollback pops destination, conditionally destroys native mutex, then Scope; successful pool escapes. |
| lib/pool.x:612 | authored function | `defer _unlock(inner);` | Reject auto/lock: private recursive/native storage or branch lock; cleanup is unlock, not destruction; preserve conditional acquisition and lock ordering. |
| lib/pool.x:633 | authored function | `defer _unlock(inner);` | Reject auto/lock: private recursive/native storage or branch lock; cleanup is unlock, not destruction; preserve conditional acquisition and lock ordering. |
| lib/pool.x:696 | authored function | `defer _unlock(inner);` | Reject auto/lock: private recursive/native storage or branch lock; cleanup is unlock, not destruction; preserve conditional acquisition and lock ordering. |
| lib/pool.x:707 | authored function | `defer _storage_unlock();` | Reject auto/lock: private recursive/native storage or branch lock; cleanup is unlock, not destruction; preserve conditional acquisition and lock ordering. |
| lib/pool.x:709 | authored function | `defer _unlock(inner);` | Reject auto/lock: private recursive/native storage or branch lock; cleanup is unlock, not destruction; preserve conditional acquisition and lock ordering. |
| lib/pool.x:729 | authored function | `defer _unlock(pool);` | Reject auto/lock: private recursive/native storage or branch lock; cleanup is unlock, not destruction; preserve conditional acquisition and lock ordering. |
| lib/pool.x:739 | authored function | `defer _unlock(inner);` | Reject auto/lock: private recursive/native storage or branch lock; cleanup is unlock, not destruction; preserve conditional acquisition and lock ordering. |
| lib/pool.x:752 | authored function | `defer _unlock(inner.up);` | Reject auto/lock: private recursive/native storage or branch lock; cleanup is unlock, not destruction; preserve conditional acquisition and lock ordering. |
| lib/pool.x:810 | authored function | `defer _storage_unlock();` | Reject auto/lock: private recursive/native storage or branch lock; cleanup is unlock, not destruction; preserve conditional acquisition and lock ordering. |
| lib/pool.x:812 | authored function | `defer if (inner) _unlock(inner);` | Reject auto/lock: private recursive/native storage or branch lock; cleanup is unlock, not destruction; preserve conditional acquisition and lock ordering. |
| lib/string.x:836 | macro template | `defer if (!$done) $string.free();` | Reject auto: mutable String buffer may become canonical result; no general String Cleanup and transfer flag matters. |
| lib/string.x:877 | authored function | `defer if (!done) string.free();` | Reject auto: mutable String buffer may become canonical result; no general String Cleanup and transfer flag matters. |
| lib/thread.x:137 | authored function | `defer Error.pop(logger_handler);` | Reject auto: Error.pop unregisters stack handler; no owned-local Cleanup adapter, and ordering matters. |
| lib/thread.x:140 | authored function | `defer Error.pop(observer);` | Reject auto: Error.pop unregisters stack handler; no owned-local Cleanup adapter, and ordering matters. |
| lib/thread.x:237 | authored function | `defer _finish_join(t);` | Reject auto: post-join finalization exports results before releasing result stores and publishing JOINED; not Thread.free. |
| lib/tokenizer.x:215 | authored function | `defer if (!mode_committed) t._pop_mode();` | Reject auto: conditional mode-stack rollback only until tokenization commits, not owned-local cleanup. |
| lib/typed-array.x:95 | authored function | `defer if ((void *) result == NULL) staged.free();` | Reject direct auto: conditional rollback frees only unsuccessful staged/created value; success returns or publishes it. Preserve ownership flag and commit boundary. |
| lib/typed-map.x:359 | authored function | `defer if ((void *) result == NULL) staged._core_free();` | Reject direct auto: conditional rollback frees only unsuccessful staged/created value; success returns or publishes it. Preserve ownership flag and commit boundary. |
| lib/typed-map.x:394 | authored function | `defer if ((void *) result == NULL) staged._core_free();` | Reject direct auto: conditional rollback frees only unsuccessful staged/created value; success returns or publishes it. Preserve ownership flag and commit boundary. |
| lib/var.x:242 | authored function | `defer x2c_descriptor_thread_start_end(0);` | Reject auto/lock: descriptor registry begin/end reservation has freeze and abort policy; not Mutex or a Cleanup value. |
