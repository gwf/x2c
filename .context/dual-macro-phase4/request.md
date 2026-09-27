# Narrowed proof requested by Gary

Investigation and isolated prototypes only. No production changes, bootstrap
refresh, commit or push outside the research branch; no publication requested
for this turn.

1. Reclassify shadow failure as pre-existing: unmodified baseline fails:
   int main(void) {
     int x2c_exception_push = 7;
     try { if (x2c_exception_push != 7) return 1; }
     finally {}
     return 0;
   }
   Native error: called object x2c_exception_push not a function/function pointer.
   Rerun open-shadow-fails.x baseline with SAME caller-local pattern; record
   identical failure, parity not regression, move blocking -> follow-up.
2. Drop per-unit scope-stack retention. Later hygiene route: resolve open free
   names while enclosing construct is parsed/scopes live, pass as bound holes
   to lowering. Existing62case control works this way. Do not prototype this
   hygiene follow-up now.
3. First proof only new-name, early, cleanup effects, transaction coverage for
   early_decls, names.adapters, needs_exception, origin. Other effects remain
   inventory added first migration needing them; same demand-driven producers.
4. Build combined isolated try lowering: compiled-in template with already
   supplied free names, actual meta slot calls for frame declaration/cleanup
   placement, three effects returned as data, source/bound/lowered carrier on
   EACH slot, extended existing transaction. Failing skeleton rollback compares
   scope+global bindings,counters,early_decls,inits,names.adapters,needs_exception,
   origin before/after. Rerun62rawC/H comparison and pairedtimings on candidate.
5. Freeze list explicitly includes fourforms, openmodifier, slotcallresult
   semantics,3stagemarks, producer table.
6. Scope sharedrole-table consolidation of _capture_pattern/_capture_row
   src/macros.x2868/3001 as FIRST productionchange on separatebranch, ordinarily
   gated/delivereddev later. Does not dependonopenitems. Do not implementnow.

Report passed, failed, thin evidence in that order.
