#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
tool=builds/x2c-graph
fixtures=tests/fixtures
tmp=${TMPDIR:-/tmp}/x2c-graph-tests.$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

builds/ast-parity "$fixtures/calls.x" >"$tmp/embedded.ast"
x2c/builds/0/x2c translate --plain --dump-ast \
  "$fixtures/calls.x" >"$tmp/cli.ast"
cmp "$tmp/embedded.ast" "$tmp/cli.ast"

sources="$fixtures/calls.x $fixtures/public-target.x \
$fixtures/collision-a.x $fixtures/collision-b.x"
$tool graph $sources >"$tmp/graph"
$tool graph "$fixtures/collision-b.x" "$fixtures/public-target.x" \
  "$fixtures/calls.x" "$fixtures/collision-a.x" >"$tmp/reversed"
cmp "$tmp/graph" "$tmp/reversed"
$tool graph -I "$fixtures" $sources >"$tmp/included"
cmp "$tmp/graph" "$tmp/included"
tr '\n' ' ' <"$tmp/graph" | sed 's/  */ /g' >"$tmp/graph-line"
if grep -q '(binding ' "$tmp/graph-line"; then
  echo "graph exposed compiler binding identities" >&2
  exit 1
fi

grep -q '(function "direct" static (calls (call direct .* "helper" 1)))' \
  "$tmp/graph-line"
grep -q \
  '(function "recursive" static (calls (call direct .* "recursive" 1)))' \
  "$tmp/graph-line"
grep -q '(call external "String_len" 1)' "$tmp/graph-line"
grep -q '(function "indirect" static (calls (call indirect "callback" 1)))' \
  "$tmp/graph-line"
grep -q '(function "computed" static (calls (call indirect "computed" 1)))' \
  "$tmp/graph-line"
grep -q '(call external "Iter_try_next" 1)' "$tmp/graph-line"
grep -q '(function "<top-level>" static (calls (call direct .* "helper" 1)))' \
  "$tmp/graph-line"
grep -q '(call direct .*public-target.x" "public_target" 1)' \
  "$tmp/graph-line"

helper_count=$(grep -o '(function "helper" static' "$tmp/graph-line" |
  wc -l | tr -d ' ')
[ "$helper_count" = 3 ]

dataset_src="$fixtures/dataset-src.x $fixtures/collision-a.x"
dataset_lib="$fixtures/dataset-lib.x $fixtures/collision-b.x"
dataset_dir="$tmp/datasets"
$tool datasets "$dataset_dir" $dataset_src -- $dataset_lib
$tool datasets "$tmp/datasets-reversed" \
  "$fixtures/collision-a.x" "$fixtures/dataset-src.x" -- \
  "$fixtures/collision-b.x" "$fixtures/dataset-lib.x"
for name in functions.tsv src-calls.tsv lib-calls.tsv; do
  cmp "$dataset_dir/$name" "$tmp/datasets-reversed/$name"
done

tab=$(printf '\t')
function_header="function_id${tab}kind${tab}subtree${tab}unit${tab}"
function_header="${function_header}unit_lines${tab}source_order${tab}"
function_header="${function_header}source_name${tab}emitted_name${tab}"
function_header="${function_header}visibility${tab}external_calls${tab}"
function_header="${function_header}indirect_calls"
[ "$(head -n 1 "$dataset_dir/functions.tsv")" = \
  "$function_header" ]
call_header="caller_id${tab}callee_id${tab}static_calls"
[ "$(head -n 1 "$dataset_dir/src-calls.tsv")" = "$call_header" ]
[ "$(head -n 1 "$dataset_dir/lib-calls.tsv")" = "$call_header" ]
[ "$(wc -l <"$dataset_dir/functions.tsv" | tr -d ' ')" = 17 ]
[ "$(wc -l <"$dataset_dir/src-calls.tsv" | tr -d ' ')" = 5 ]
[ "$(wc -l <"$dataset_dir/lib-calls.tsv" | tr -d ' ')" = 6 ]

method="dataset-src.x::DatasetValue_read${tab}function${tab}src${tab}"
method="${method}.*${tab}38${tab}2${tab}DatasetValue.read${tab}"
method="${method}DatasetValue_read${tab}public${tab}0${tab}0$"
grep -q "$method" \
  "$dataset_dir/functions.tsv"
top_level="dataset-src.x::<top-level>${tab}top-level${tab}src${tab}"
top_level="${top_level}.*${tab}38${tab}0${tab}<top-level>${tab}"
top_level="${top_level}<top-level>${tab}static${tab}0${tab}0$"
grep -q "$top_level" \
  "$dataset_dir/functions.tsv"
external="dataset-src.x::dataset_src_external${tab}function${tab}src${tab}"
external="${external}.*${tab}38${tab}6${tab}dataset_src_external${tab}"
external="${external}dataset_src_external${tab}static${tab}1${tab}0$"
grep -q "$external" \
  "$dataset_dir/functions.tsv"
indirect="dataset-src.x::dataset_src_indirect${tab}function${tab}src${tab}"
indirect="${indirect}.*${tab}38${tab}7${tab}dataset_src_indirect${tab}"
indirect="${indirect}dataset_src_indirect${tab}static${tab}0${tab}1$"
grep -q "$indirect" \
  "$dataset_dir/functions.tsv"
grep -q "collision-a.x::helper${tab}function${tab}src${tab}" \
  "$dataset_dir/functions.tsv"
grep -q "collision-b.x::helper${tab}function${tab}lib${tab}" \
  "$dataset_dir/functions.tsv"

grep -q "dataset-src.x::dataset_src_repeated${tab}.*\
dataset-src.x::dataset_src_helper${tab}2$" \
  "$dataset_dir/src-calls.tsv"
grep -q "dataset-src.x::<top-level>${tab}.*\
dataset-src.x::dataset_src_helper${tab}1$" \
  "$dataset_dir/src-calls.tsv"
grep -q "dataset-src.x::dataset_src_to_lib${tab}.*\
dataset-lib.x::dataset_lib_public${tab}1$" \
  "$dataset_dir/lib-calls.tsv"
grep -q "dataset-lib.x::dataset_lib_to_src${tab}.*\
dataset-src.x::dataset_src_public${tab}1$" \
  "$dataset_dir/lib-calls.tsv"
grep -q "dataset-lib.x::dataset_lib_public${tab}.*\
dataset-lib.x::dataset_lib_helper${tab}1$" \
  "$dataset_dir/lib-calls.tsv"

duplicates="$tmp/dataset-duplicate-ids"
tail -n +2 "$dataset_dir/functions.tsv" | cut -f1 | sort | uniq -d \
  >"$duplicates"
test ! -s "$duplicates"
awk -F '\t' '
  NR == FNR { if (FNR > 1) nodes[$1]++; next }
  FNR > 1 && (nodes[$1] != 1 || nodes[$2] != 1) { exit 1 }
' "$dataset_dir/functions.tsv" "$dataset_dir/src-calls.tsv" \
  "$dataset_dir/lib-calls.tsv"

$tool focus helper $sources >"$tmp/focus"
$tool focus helper "$fixtures/collision-b.x" \
  "$fixtures/public-target.x" "$fixtures/calls.x" \
  "$fixtures/collision-a.x" >"$tmp/focus-reversed"
cmp "$tmp/focus" "$tmp/focus-reversed"
tr '\n' ' ' <"$tmp/focus" | sed 's/  */ /g' >"$tmp/focus-line"
focus_helper_count=$(grep -o '"helper" static' \
  "$tmp/focus-line" | wc -l | tr -d ' ')
[ "$focus_helper_count" = 3 ]
grep -q '(function .*collision-a.x" "helper" static (callers (function .*collision-a.x" "collision_a" public 1)) (calls))' \
  "$tmp/focus-line"
grep -q '(function .*calls.x" "helper" static (callers (function .*calls.x" "<top-level>" static 1) (function .*calls.x" "direct" static 1)) (calls))' \
  "$tmp/focus-line"

$tool focus resolved_method $sources >"$tmp/focus-method"
grep -q '(call external "String_len" 1)' "$tmp/focus-method"
$tool focus expanded $sources >"$tmp/focus-macro"
grep -q '(call external "Iter_try_next" 1)' "$tmp/focus-macro"

$tool focus unknown_function $sources >"$tmp/focus-empty"
tr '\n' ' ' <"$tmp/focus-empty" | sed 's/  */ /g' >"$tmp/focus-empty-line"
grep -q '^(focus "unknown_function" (matches))' "$tmp/focus-empty-line"

$tool digest $sources >"$tmp/digest"
tr '\n' ' ' <"$tmp/digest" | sed 's/  */ /g' >"$tmp/digest-line"
grep -q '^(digest (totals (units 4)' "$tmp/digest-line"
grep -q '(cycles)' "$tmp/digest"

$tool graph "$fixtures/ambiguous-a.x" "$fixtures/ambiguous-b.x" \
  "$fixtures/ambiguous-call.x" >"$tmp/ambiguous"
grep -q '(call external "duplicate_target" 1)' "$tmp/ambiguous"

$tool digest "$fixtures/cycle-a.x" "$fixtures/cycle-b.x" \
  >"$tmp/cycle"
tr '\n' ' ' <"$tmp/cycle" | sed 's/  */ /g' >"$tmp/cycle-line"
grep -q '(cycle .*cycle-a.x" .*cycle-b.x")' "$tmp/cycle-line"

architecture_sources="$fixtures/architecture-a.x \
$fixtures/architecture-b.x"
$tool architecture $architecture_sources >"$tmp/architecture"
$tool architecture "$fixtures/architecture-b.x" \
  "$fixtures/architecture-a.x" >"$tmp/architecture-reversed"
cmp "$tmp/architecture" "$tmp/architecture-reversed"
tr '\n' ' ' <"$tmp/architecture" | sed 's/  */ /g' \
  >"$tmp/architecture-line"
thresholds='^(architecture (limit 25) (thresholds (unit-functions 20) '
thresholds="$thresholds(component-functions 2) (reciprocal-calls 2) "
thresholds="$thresholds(boundary-functions 2) (bridge-second-group 2))"
grep -q "$thresholds" "$tmp/architecture-line"
grep -q \
  '(function .*architecture-a.x" "architecture_shared" public (callers (cross-units 1) (units 1) (functions 2)) (calls 2))' \
  "$tmp/architecture-line"
grep -q \
  '(function .*architecture-b.x" "architecture_b" public (callers (cross-units 1) (units 1) (functions 1)) (calls 2))' \
  "$tmp/architecture-line"
grep -q \
  '(units .*architecture-a.x" .*architecture-b.x" (calls (.*architecture-a.x" .*architecture-b.x" 2) (.*architecture-b.x" .*architecture-a.x" 2)))' \
  "$tmp/architecture-line"
dependency='(dependency-width (units .*architecture-a.x" '
dependency="$dependency.*architecture-b.x\" (functions "
dependency="$dependency(.*architecture-a.x\" 2) "
dependency="$dependency(.*architecture-b.x\" 2)) (directions "
dependency="$dependency(direction .*architecture-a.x\" "
dependency="$dependency.*architecture-b.x\" "
dependency="$dependency(functions (callers 1) (callees 1)) "
dependency="$dependency(edges 1) (calls 2)) "
dependency="$dependency(direction .*architecture-b.x\" "
dependency="$dependency.*architecture-a.x\" "
dependency="$dependency(functions (callers 2) (callees 1)) "
dependency="$dependency(edges 2) (calls 2)))))"
grep -q "$dependency" "$tmp/architecture-line"
grep -q \
  '(function .*architecture-a.x" "architecture_bridge" (groups 2 2 1))' \
  "$tmp/architecture-line"

$tool structure "$fixtures/architecture-a.x" $architecture_sources \
  >"$tmp/structure"
$tool structure "$fixtures/architecture-a.x" \
  "$fixtures/architecture-b.x" "$fixtures/architecture-a.x" \
  >"$tmp/structure-reversed"
cmp "$tmp/structure" "$tmp/structure-reversed"
tr '\n' ' ' <"$tmp/structure" | sed 's/  */ /g' \
  >"$tmp/structure-line"
grep -q \
  '(functions 11) (internal 6) (isolated "architecture_isolated" "architecture_shared" "architecture_to_b")' \
  "$tmp/structure-line"
grep -q \
  '(component.*architecture_detached" "architecture_detached_leaf")' \
  "$tmp/structure-line"
grep -q \
  '(function "architecture_bridge" (groups (group "architecture_left" "architecture_left_leaf") (group "architecture_right" "architecture_right_leaf") (group "architecture_root")))' \
  "$tmp/structure-line"
$tool structure missing.x $architecture_sources >"$tmp/structure-empty"
grep -q '^(structure "missing.x" (matches))' "$tmp/structure-empty"

$tool between "$fixtures/architecture-a.x" \
  "$fixtures/architecture-b.x" $architecture_sources >"$tmp/between"
$tool between "$fixtures/architecture-a.x" \
  "$fixtures/architecture-b.x" "$fixtures/architecture-b.x" \
  "$fixtures/architecture-a.x" >"$tmp/between-reversed"
cmp "$tmp/between" "$tmp/between-reversed"
tr '\n' ' ' <"$tmp/between" | sed 's/  */ /g' >"$tmp/between-line"
grep -q \
  '(direction .*architecture-a.x" .*architecture-b.x" (count 2) (calls (call "architecture_to_b" static "architecture_b" 2)))' \
  "$tmp/between-line"
grep -q \
  '(direction .*architecture-b.x" .*architecture-a.x" (count 2) (calls (call "architecture_b" public "architecture_shared" 1) (call "architecture_b_helper" static "architecture_shared" 1)))' \
  "$tmp/between-line"
$tool between missing.x "$fixtures/architecture-a.x" \
  $architecture_sources >"$tmp/between-empty"
tr '\n' ' ' <"$tmp/between-empty" | sed 's/  */ /g' \
  >"$tmp/between-empty-line"
grep -q '(direction "missing.x" .*architecture-a.x" (count 0) (calls))' \
  "$tmp/between-empty-line"

field_sources="$fixtures/fields-a.x $fixtures/fields-b.x"
$tool field FieldOwner value $field_sources >"$tmp/field"
$tool field FieldOwner value "$fixtures/fields-b.x" \
  "$fixtures/fields-a.x" >"$tmp/field-reversed"
cmp "$tmp/field" "$tmp/field-reversed"
tr '\n' ' ' <"$tmp/field" | sed 's/  */ /g' >"$tmp/field-line"
grep -q '(function "field_read" static (reads 1) (lvalues 0))' \
  "$tmp/field-line"
for function in field_assign field_compound field_prefix field_postfix; do
  grep -q "(function \"$function\" static (reads 0) (lvalues 1))" \
    "$tmp/field-line"
done
grep -q \
  '(function "second_field_read" public (reads 1) (lvalues 0))' \
  "$tmp/field-line"
if grep -q 'other_field_read' "$tmp/field-line"; then
  echo "field query ignored its receiver type" >&2
  exit 1
fi

$tool field FieldOwner values "$fixtures/fields-a.x" \
  >"$tmp/field-indexed"
grep -q \
  '(function "field_indexed" static (reads 0) (lvalues 1))' \
  "$tmp/field-indexed"
$tool field OtherOwner value "$fixtures/fields-a.x" \
  >"$tmp/field-selector"
grep -q \
  '(function "field_indexed" static (reads 1) (lvalues 0))' \
  "$tmp/field-selector"
$tool field FieldOwner entries "$fixtures/fields-a.x" \
  >"$tmp/field-mapped"
grep -q \
  '(function "field_mapped" static (reads 0) (lvalues 1))' \
  "$tmp/field-mapped"

$tool field UnknownOwner missing $field_sources >"$tmp/field-empty"
tr '\n' ' ' <"$tmp/field-empty" | sed 's/  */ /g' \
  >"$tmp/field-empty-line"
grep -q '^(field "UnknownOwner" "missing" (units))' \
  "$tmp/field-empty-line"

$tool field-sites FieldOwner value $field_sources >"$tmp/field-sites"
$tool field-sites FieldOwner value "$fixtures/fields-b.x" \
  "$fixtures/fields-a.x" >"$tmp/field-sites-reversed"
cmp "$tmp/field-sites" "$tmp/field-sites-reversed"
tr '\n' ' ' <"$tmp/field-sites" | sed 's/  */ /g' \
  >"$tmp/field-sites-line"
grep -q '"field_read" static (location .*fields-a.x" [1-9][0-9]* [1-9][0-9]*) (access read)' \
  "$tmp/field-sites-line"
grep -q '"field_assign" static .* (access replace (value (int) (literal "1")))' \
  "$tmp/field-sites-line"
grep -q '"field_replace_parameter" static .* (access replace (value (int) (parameter "value")))' \
  "$tmp/field-sites-line"
grep -q '"field_replace_and_read" static .* (access read)' \
  "$tmp/field-sites-line"
grep -q '"field_double_read" static .* (access read) (count 2)' \
  "$tmp/field-sites-line"
for function in field_compound field_prefix field_postfix; do
  grep -q "\"$function\" static .* (access mutate)" \
    "$tmp/field-sites-line"
done
$tool field-sites FieldOwner values "$fixtures/fields-a.x" \
  >"$tmp/field-sites-indexed"
tr '\n' ' ' <"$tmp/field-sites-indexed" | sed 's/  */ /g' \
  >"$tmp/field-sites-indexed-line"
grep -q '"field_indexed" static .* (access mutate)' \
  "$tmp/field-sites-indexed-line"
$tool field-sites UnknownOwner missing $field_sources \
  >"$tmp/field-sites-empty"
grep -q '^(field-sites "UnknownOwner" "missing" (sites))' \
  "$tmp/field-sites-empty"
if grep -q '(binding \|(cache \|(origin ' "$tmp/field-sites-line"; then
  echo "field-sites exposed compiler identities" >&2
  exit 1
fi

if $tool field-sites FieldOwner value "$fixtures/malformed.x" \
     >"$tmp/field-sites-bad.out" 2>"$tmp/field-sites-bad.err"; then
  echo "malformed field-sites input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/field-sites-bad.out"
test -s "$tmp/field-sites-bad.err"

site_sources="$fixtures/sites-a.x $fixtures/sites-b.x"
$tool sites site_target $site_sources >"$tmp/sites"
$tool sites site_target "$fixtures/sites-b.x" \
  "$fixtures/sites-a.x" >"$tmp/sites-reversed"
cmp "$tmp/sites" "$tmp/sites-reversed"
$tool sites site_target -I "$fixtures" $site_sources \
  >"$tmp/sites-included"
cmp "$tmp/sites" "$tmp/sites-included"
tr '\n' ' ' <"$tmp/sites" | sed 's/  */ /g' >"$tmp/sites-line"

for summary in \
  '(parameter "parameter")' \
  '(local "local" (prior-writes (call "site_make")))' \
  '(field ("SiteOwner") "value")' \
  '(call "site_make")' \
  '(literal "7")' \
  '(operator +)' \
  '(index (field ("SiteOwner") "values"))' \
  '(cast (local "local"' \
  '(argument ("List") (list))' \
  '(argument ("Map") (map))' \
  '(argument ("Array") (array))' \
  '(call computed)' \
  '(global "site_global")' \
  '(form sizeof)'
do
  grep -Fq "$summary" "$tmp/sites-line"
done
grep -Fq '"site_shapes" static 2' "$tmp/sites-line"
grep -q \
  '"site_shapes" static 1 .*prior-writes (call "site_make") (literal "9")' \
  "$tmp/sites-line"
branch_pattern='"site_branches" static 1 .*prior-writes (call "site_make")'
branch_pattern="$branch_pattern (literal \"4\") (literal \"5\")"
grep -q "$branch_pattern" "$tmp/sites-line"
mutation_pattern='"site_mutations" static 1 .*prior-writes (call "site_make")'
mutation_pattern="$mutation_pattern (operator ++) (operator +=)"
grep -q "$mutation_pattern" "$tmp/sites-line"
if grep -q '(binding \|(cache ' "$tmp/sites-line"; then
  echo "sites exposed compiler binding or cache identities" >&2
  exit 1
fi

$tool sites shared_site $site_sources >"$tmp/sites-static"
tr '\n' ' ' <"$tmp/sites-static" | sed 's/  */ /g' \
  >"$tmp/sites-static-line"
grep -q 'sites-a.x" .*"first_shared_caller" static 1' \
  "$tmp/sites-static-line"
grep -q 'sites-b.x" .*"second_shared_caller" public 1' \
  "$tmp/sites-static-line"

$tool sites Iter_try_next "$fixtures/calls.x" >"$tmp/sites-macro"
grep -q '"expanded" static 1' "$tmp/sites-macro"

$tool sites site_make $site_sources >"$tmp/sites-top-level"
grep -q '"<top-level>" static 1' "$tmp/sites-top-level"

$tool sites unknown_function $site_sources >"$tmp/sites-empty"
tr '\n' ' ' <"$tmp/sites-empty" | sed 's/  */ /g' \
  >"$tmp/sites-empty-line"
grep -q '^(sites "unknown_function" (calls))' \
  "$tmp/sites-empty-line"

$tool walks "$fixtures/walks.x" "$fixtures/calls.x" x2c/lib/list.x \
  >"$tmp/walks"
$tool walks x2c/lib/list.x "$fixtures/calls.x" "$fixtures/walks.x" \
  >"$tmp/walks-reversed"
cmp "$tmp/walks" "$tmp/walks-reversed"
tr '\n' ' ' <"$tmp/walks" | sed 's/  */ /g' >"$tmp/walks-line"
grep -q \
  '(candidate "combined_walk" static (argument ("List") "value") (walkers "first_walk" "second_walk")' \
  "$tmp/walks-line"
grep -q \
  '(candidate "field_walk" static (argument ("List") "value.first") (walkers "first_walk" "second_walk")' \
  "$tmp/walks-line"
grep -q \
  '(candidate "nested_field_walk" static (argument ("List") "tree.leaf.nodes") (walkers "first_walk" "second_walk")' \
  "$tmp/walks-line"
grep -q \
  '(candidate "pointer_field_walk" static (argument ("List") "holder.field") (walkers "first_walk" "second_walk")' \
  "$tmp/walks-line"
grep -q \
  '(candidate "combined_linear_walk" static (argument ("List") "value") (walkers "linear_first" "linear_second")' \
  "$tmp/walks-line"
grep -q \
  '(candidate "repeated_linear_walk" static (argument ("List") "value") (walkers "linear_first") (sites (site "linear_first" (location "' \
  "$tmp/walks-line"
grep -q \
  '(candidate "combined_wrapper_walk" static (argument ("List") "value") (walkers "linear_second" "linear_wrapper")' \
  "$tmp/walks-line"
grep -q \
  '(candidate "inline_and_len_walk" static (argument ("List") "value") (walkers "<inline>" "List_len")' \
  "$tmp/walks-line"
for rejected in separate_walk different_field_walk different_root_walk \
  call_receiver_walk index_receiver_walk dereference_receiver_walk \
  assignment_argument_walk combined_early_exit_walk
do
  if grep -q "$rejected" "$tmp/walks-line"; then
    echo "walks combined an unstable or different argument" >&2
    exit 1
  fi
done
$tool walks "$fixtures/calls.x" >"$tmp/walks-empty"
grep -q '^(walks (units))' "$tmp/walks-empty"

$tool tail-calls "$fixtures/tail-calls.x" "$fixtures/calls.x" \
  >"$tmp/tail-calls"
$tool tail-calls "$fixtures/calls.x" "$fixtures/tail-calls.x" \
  >"$tmp/tail-calls-reversed"
cmp "$tmp/tail-calls" "$tmp/tail-calls-reversed"
tr '\n' ' ' <"$tmp/tail-calls" | sed 's/  */ /g' \
  >"$tmp/tail-calls-line"
grep -q \
  '(function "tail_only" static (calls (tail 1) (non-tail 0)) (blockers)' \
  "$tmp/tail-calls-line"
grep -q \
  '(function "mixed_tail" static (calls (tail 1) (non-tail 1)) (blockers)' \
  "$tmp/tail-calls-line"
cleanup_tail='(function "cleanup_tail" static (calls (tail 1) '
cleanup_tail="$cleanup_tail(non-tail 0)) (blockers cleanup)"
grep -q "$cleanup_tail" "$tmp/tail-calls-line"
grep -q \
  '(function "conditional_tail" static (calls (tail 1) (non-tail 0))' \
  "$tmp/tail-calls-line"
grep -q \
  '(function "nested_conditional_tail" static (calls (tail 2) (non-tail 0))' \
  "$tmp/tail-calls-line"
grep -q \
  '(function "conditional_mixed" static (calls (tail 1) (non-tail 2))' \
  "$tmp/tail-calls-line"
conditional_cleanup='(function "conditional_cleanup" static (calls (tail 1) '
conditional_cleanup="$conditional_cleanup(non-tail 0)) (blockers cleanup)"
grep -q "$conditional_cleanup" "$tmp/tail-calls-line"
for name in non_tail_only conditional_condition_only conditional_non_tail; do
  if grep -q "\"$name\"" "$tmp/tail-calls-line"; then
    echo "tail-calls reported a function without a tail self-call" >&2
    exit 1
  fi
done

$tool loop-allocations "$fixtures/loop-allocations.x" "$fixtures/calls.x" \
  >"$tmp/loop-allocations"
$tool loop-allocations "$fixtures/calls.x" "$fixtures/loop-allocations.x" \
  >"$tmp/loop-allocations-reversed"
cmp "$tmp/loop-allocations" "$tmp/loop-allocations-reversed"
tr '\n' ' ' <"$tmp/loop-allocations" | sed 's/  */ /g' \
  >"$tmp/loop-allocations-line"
loop_summary='^(loop-allocations (summary (functions 4) (expressions 6) '
loop_summary="$loop_summary(direct (pooled 5) (scoped 2)) "
loop_summary="$loop_summary(helper-calls (pooled 0) (scoped 0)) (reported 6))"
grep -q "$loop_summary" "$tmp/loop-allocations-line"
returned='(site .* "returned_allocation" static .*'
returned="$returned(allocations (direct (pooled 2) (scoped 0)) "
returned="$returned(helper-calls (pooled 0) (scoped 0))) "
returned="$returned(uses (returned 1) (assigned 0) (argument 1)"
grep -q "$returned" "$tmp/loop-allocations-line"
grep -q '(operations (direct "String_new" 1) (direct "cons" 1))' \
  "$tmp/loop-allocations-line"
if grep -q 'one_allocation' "$tmp/loop-allocations-line"; then
  echo "loop-allocations reported a one-time allocation" >&2
  exit 1
fi
if grep -q '(binding \|(cache \|(origin ' "$tmp/loop-allocations-line"; then
  echo "loop-allocations exposed compiler identities" >&2
  exit 1
fi

$tool loop-allocations "$fixtures/lifetime-summaries.x" \
  "$fixtures/lifetime-summary-public.x" \
  "$fixtures/lifetime-summary-ambiguous.x" >"$tmp/loop-summaries"
$tool loop-allocations "$fixtures/lifetime-summary-ambiguous.x" \
  "$fixtures/lifetime-summary-public.x" \
  "$fixtures/lifetime-summaries.x" >"$tmp/loop-summaries-reversed"
cmp "$tmp/loop-summaries" "$tmp/loop-summaries-reversed"
tr '\n' ' ' <"$tmp/loop-summaries" | sed 's/  */ /g' \
  >"$tmp/loop-summaries-line"
helper_summary='^(loop-allocations (summary (functions 1) (expressions 6) '
helper_summary="$helper_summary(direct (pooled 0) (scoped 0)) "
helper_summary="$helper_summary(helper-calls (pooled 1) (scoped 5)) "
helper_summary="$helper_summary(reported 6))"
grep -q "$helper_summary" "$tmp/loop-summaries-line"
for helper in _summary_direct _summary_transitive _summary_static \
  _summary_recursive_seed summary_public _summary_pooled
do
  grep -q "(helper \"$helper\" \(scoped\|pooled\) 1)" \
    "$tmp/loop-summaries-line"
done
for helper in _summary_recursive _summary_indirect _summary_mixed \
  _summary_converted summary_ambiguous summary_missing
do
  if grep -q "(helper \"$helper\"" "$tmp/loop-summaries-line"; then
    echo "loop-allocations resolved uncertain helper $helper" >&2
    exit 1
  fi
done

$tool loop-allocations "$fixtures/loop-ranking.x" >"$tmp/loop-ranking"
tr '\n' ' ' <"$tmp/loop-ranking" | sed 's/  */ /g' \
  >"$tmp/loop-ranking-line"
ranking_summary='^(loop-allocations (summary (functions 26) (expressions 26) '
ranking_summary="$ranking_summary(direct (pooled 24) (scoped 2)) "
ranking_summary="$ranking_summary(helper-calls (pooled 1) (scoped 0)) "
ranking_summary="$ranking_summary(reported 25))"
grep -q "$ranking_summary" "$tmp/loop-ranking-line"
ranking_names=$(grep -o '(site "[^"]*" "[^"]*"' \
  "$tmp/loop-ranking-line" | head -6 | sed 's/.*"\([^"]*\)"$/\1/' |
  paste -sd ' ' -)
expected_ranking='rank_scoped_array rank_scoped_map rank_discarded rank_helper'
expected_ranking="$expected_ranking rank_total rank_depth"
test "$ranking_names" = "$expected_ranking"
grep -q '"tie_19"' "$tmp/loop-ranking-line"
if grep -q '"tie_20"' "$tmp/loop-ranking-line"; then
  echo "loop-allocations exceeded its ranked candidate limit" >&2
  exit 1
fi
$tool loop-allocations --all "$fixtures/loop-ranking.x" \
  >"$tmp/loop-ranking-all"
tr '\n' ' ' <"$tmp/loop-ranking-all" | sed 's/  */ /g' \
  >"$tmp/loop-ranking-all-line"
grep -q '(reported 26)' "$tmp/loop-ranking-all-line"
grep -q '"tie_20"' "$tmp/loop-ranking-all-line"

if $tool loop-allocations "$fixtures/loop-allocations.x" \
     "$fixtures/malformed.x" >"$tmp/loop-bad.out" \
     2>"$tmp/loop-bad.err"; then
  echo "malformed loop-allocations input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/loop-bad.out"
test -s "$tmp/loop-bad.err"

if $tool loop-allocations "$fixtures/loop-allocations.x" \
     "$fixtures/missing.x" >"$tmp/loop-missing.out" \
     2>"$tmp/loop-missing.err"; then
  echo "missing loop-allocations input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/loop-missing.out"
grep -q 'cannot read input file' "$tmp/loop-missing.err"

$tool lifetime-escapes "$fixtures/lifetime-escapes.x" \
  "$fixtures/calls.x" >"$tmp/lifetime-escapes"
$tool lifetime-escapes "$fixtures/calls.x" \
  "$fixtures/lifetime-escapes.x" >"$tmp/lifetime-escapes-reversed"
cmp "$tmp/lifetime-escapes" "$tmp/lifetime-escapes-reversed"
tr '\n' ' ' <"$tmp/lifetime-escapes" | sed 's/  */ /g' \
  >"$tmp/lifetime-escapes-line"
summary='^(lifetime-escapes (summary (regions 13) (allocations 12) '
summary="$summary(transfers 2) (unresolved 3) (findings 6))"
grep -q "$summary" "$tmp/lifetime-escapes-line"
for function in lifetime_scope_alias lifetime_scope_deferred \
  lifetime_context_unexported lifetime_context_ignored_export \
  lifetime_context_deferred lifetime_context_mutable
do
  grep -q "finding dangling-return .*\"$function\"" \
    "$tmp/lifetime-escapes-line"
done
for function in lifetime_scope_moved lifetime_context_exported \
  lifetime_context_inherited
do
  if grep -q "\"$function\"" "$tmp/lifetime-escapes-line"; then
    echo "lifetime-escapes reported $function" >&2
    exit 1
  fi
done
unknown='call .*lifetime-escapes.x" "lifetime_unknown" '
unknown="$unknown\"lifetime_native\" (location .*lifetime-escapes.x\" 28 3)"
grep -q "$unknown" "$tmp/lifetime-escapes-line"
indirect='call .*lifetime-escapes.x" "lifetime_indirect" '
indirect="$indirect\"computed\" (location .*lifetime-escapes.x\" 79 3)"
grep -q "$indirect" "$tmp/lifetime-escapes-line"
branch_unknown='call .*lifetime-escapes.x" "lifetime_branch_unknown" '
branch_unknown="$branch_unknown\"lifetime_native\" "
branch_unknown="$branch_unknown(location .*lifetime-escapes.x\" 87 3)"
grep -q "$branch_unknown" "$tmp/lifetime-escapes-line"
if grep -q 'lifetime_branch_assignment' "$tmp/lifetime-escapes-line"; then
  echo "lifetime-escapes followed a branch assignment" >&2
  exit 1
fi
scope_alias='"lifetime_scope_alias" scope "Scope_memdup" '
scope_alias="$scope_alias(allocated (location .*lifetime-escapes.x\" 5 3)) "
scope_alias="$scope_alias(ended (location .*lifetime-escapes.x\" 7 3)) "
scope_alias="$scope_alias(returned (location .*lifetime-escapes.x\" 8 3))"
grep -q "$scope_alias" "$tmp/lifetime-escapes-line"
context_deferred='"lifetime_context_deferred" context "String_new" '
context_deferred="$context_deferred(allocated (location "
context_deferred="$context_deferred.*lifetime-escapes.x\" 59 3)) "
context_deferred="$context_deferred(ended (location "
context_deferred="$context_deferred.*lifetime-escapes.x\" 58 3)) "
context_deferred="$context_deferred(returned (location "
context_deferred="$context_deferred.*lifetime-escapes.x\" 59 3))"
grep -q "$context_deferred" "$tmp/lifetime-escapes-line"
if grep -q '(binding \|(cache \|(origin ' "$tmp/lifetime-escapes-line"; then
  echo "lifetime-escapes exposed compiler identities" >&2
  exit 1
fi

$tool lifetime-escapes "$fixtures/lifetime-summaries.x" \
  "$fixtures/lifetime-summary-public.x" \
  "$fixtures/lifetime-summary-ambiguous.x" >"$tmp/lifetime-summaries"
$tool lifetime-escapes "$fixtures/lifetime-summary-ambiguous.x" \
  "$fixtures/lifetime-summary-public.x" \
  "$fixtures/lifetime-summaries.x" >"$tmp/lifetime-summaries-reversed"
cmp "$tmp/lifetime-summaries" "$tmp/lifetime-summaries-reversed"
tr '\n' ' ' <"$tmp/lifetime-summaries" | sed 's/  */ /g' \
  >"$tmp/lifetime-summaries-line"
summary='^(lifetime-escapes (summary (regions 12) (allocations 6) '
summary="$summary(transfers 0) (unresolved 6) (findings 6))"
grep -q "$summary" "$tmp/lifetime-summaries-line"
for function in summary_direct_escape summary_transitive_escape \
  summary_static_escape summary_recursive_seed_escape summary_public_escape \
  summary_pooled_escape
do
  grep -q "finding dangling-return \"[^\"]*\" \"$function\"" \
    "$tmp/lifetime-summaries-line"
done
for function in summary_recursive_unknown summary_indirect_unknown \
  summary_mixed_unknown summary_conversion_unknown \
  summary_ambiguous_unknown summary_missing_unknown
do
  grep -q "call \"[^\"]*\" \"$function\"" \
    "$tmp/lifetime-summaries-line"
done
direct_summary='"summary_direct_escape" scope "_summary_direct" '
direct_summary="$direct_summary(allocated (location "
direct_summary="$direct_summary.*lifetime-summaries.x\" 43 3))"
grep -q "$direct_summary" "$tmp/lifetime-summaries-line"
public_summary='"summary_public_escape" scope "summary_public" '
public_summary="$public_summary(allocated (location "
public_summary="$public_summary.*lifetime-summaries.x\" 71 3))"
grep -q "$public_summary" "$tmp/lifetime-summaries-line"

$tool allocation-returns _summary_list_free \
  "$fixtures/lifetime-summaries.x" \
  "$fixtures/lifetime-summary-public.x" \
  "$fixtures/lifetime-summary-ambiguous.x" >"$tmp/allocation-returns"
$tool allocation-returns _summary_list_free \
  "$fixtures/lifetime-summary-ambiguous.x" \
  "$fixtures/lifetime-summary-public.x" \
  "$fixtures/lifetime-summaries.x" >"$tmp/allocation-returns-reversed"
cmp "$tmp/allocation-returns" "$tmp/allocation-returns-reversed"
tr '\n' ' ' <"$tmp/allocation-returns" | sed 's/  */ /g' \
  >"$tmp/allocation-returns-line"
grep -q '^(allocation-returns "_summary_list_free" (summary (returns 1))' \
  "$tmp/allocation-returns-line"
grep -q '"_summary_list_free" pooled "Array_list_free"' \
  "$tmp/allocation-returns-line"
if grep -q '(binding \|(cache \|(origin ' "$tmp/allocation-returns-line"; then
  echo "allocation-returns exposed compiler identities" >&2
  exit 1
fi
if grep -q '(binding \|(cache \|(origin ' "$tmp/lifetime-summaries-line"; then
  echo "lifetime summaries exposed compiler identities" >&2
  exit 1
fi

flow_sources="$fixtures/flows-a.x $fixtures/flows-b.x \
$fixtures/flows-ambiguous.x"
$tool flows flow_produce flow_consume $flow_sources >"$tmp/flows"
$tool flows flow_produce flow_consume \
  "$fixtures/flows-ambiguous.x" "$fixtures/flows-b.x" \
  "$fixtures/flows-a.x" >"$tmp/flows-reversed"
cmp "$tmp/flows" "$tmp/flows-reversed"
tr '\n' ' ' <"$tmp/flows" | sed 's/  */ /g' >"$tmp/flows-line"
grep -q '(step producer .*flows-a.x" "flow_produce")' \
  "$tmp/flows-line"
grep -q '(step local "produced" .* (step assignment "assigned"' \
  "$tmp/flows-line"
grep -q '(argument 1 (identifier "AST_FIELD"))' "$tmp/flows-line"
grep -q '(argument 1 (identifier "AST_MAP_ENTRY"))' "$tmp/flows-line"
for reason in ambiguous-call computed-call field-storage mutation; do
  grep -q "(unresolved \"$reason\"" "$tmp/flows-line"
done
if grep -q '(binding \|(cache \|(origin ' "$tmp/flows-line"; then
  echo "flows exposed compiler identities" >&2
  exit 1
fi

$tool flows helper_produce helper_consume \
  "$fixtures/flows-helper.x" >"$tmp/flows-helper"
tr '\n' ' ' <"$tmp/flows-helper" | sed 's/  */ /g' \
  >"$tmp/flows-helper-line"
grep -q '(step return .* (step call "helper_return_producer"' \
  "$tmp/flows-helper-line"
grep -q '(step call "helper_return_parameter"' \
  "$tmp/flows-helper-line"
grep -q '(step call "helper_consume_parameter"' \
  "$tmp/flows-helper-line"
grep -q '(argument 1 (identifier "AST_STATEMENT"))' \
  "$tmp/flows-helper-line"

$tool flows alias_produce alias_consume \
  "$fixtures/flows-alias.x" >"$tmp/flows-alias"
grep -q '(paths)' "$tmp/flows-alias"
grep -q '(unresolved "alias-merge"' "$tmp/flows-alias"

$tool flows control_produce control_consume \
  "$fixtures/flows-control.x" >"$tmp/flows-control"
tr '\n' ' ' <"$tmp/flows-control" | sed 's/  */ /g' \
  >"$tmp/flows-control-line"
grep -q '(step local "produced"' "$tmp/flows-control-line"
grep -q '(step return .* (step call "control_return"' \
  "$tmp/flows-control-line"
grep -q '(step return .* (step call "control_try_return"' \
  "$tmp/flows-control-line"
grep -q '(argument 1 (identifier "AST_MAP_ENTRY"))' \
  "$tmp/flows-control-line"
grep -q '(unresolved "alias-merge"' "$tmp/flows-control-line"

$tool flows address_produce address_consume \
  "$fixtures/flows-control.x" >"$tmp/flows-address"
grep -q '(paths)' "$tmp/flows-address"
grep -q '(unresolved "address-mutation"' "$tmp/flows-address"

$tool flows expression_produce expression_consume \
  "$fixtures/flows-control.x" >"$tmp/flows-expression"
tr '\n' ' ' <"$tmp/flows-expression" | sed 's/  */ /g' \
  >"$tmp/flows-expression-line"
grep -q '(step producer .*"expression_produce"' \
  "$tmp/flows-expression-line"

$tool compare flow_direct flow_return_chain flow_consume flow_produce \
  flow_return_parameter -- "$fixtures/flows-a.x" >"$tmp/compare"
$tool compare flow_direct flow_return_chain flow_return_parameter \
  flow_produce flow_consume -- "$fixtures/flows-a.x" \
  >"$tmp/compare-reversed"
cmp "$tmp/compare" "$tmp/compare-reversed"
tr '\n' ' ' <"$tmp/compare" | sed 's/  */ /g' >"$tmp/compare-line"
grep -q '(operation "flow_consume" both' "$tmp/compare-line"
grep -q '(operation "flow_produce" both' "$tmp/compare-line"
grep -q '(operation "flow_return_parameter" right-only' \
  "$tmp/compare-line"
compare_path='"flow_return_chain" static.*"flow_return_producer" static'
compare_path="$compare_path.*\"flow_produce\" public"
grep -q "$compare_path" \
  "$tmp/compare-line"
grep -q '(left (unproved "unreachable"))' "$tmp/compare-line"

if $tool flows flow_produce flow_consume "$fixtures/flows-a.x" \
     "$fixtures/malformed.x" >"$tmp/flows-bad.out" \
     2>"$tmp/flows-bad.err"; then
  echo "malformed flows input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/flows-bad.out"
test -s "$tmp/flows-bad.err"

if $tool flows flow_produce flow_consume "$fixtures/missing.x" \
     >"$tmp/flows-missing.out" 2>"$tmp/flows-missing.err"; then
  echo "missing flows input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/flows-missing.out"
grep -q 'cannot read input file' "$tmp/flows-missing.err"

if $tool compare flow_direct flow_return_chain flow_consume -- \
     "$fixtures/malformed.x" >"$tmp/compare-bad.out" \
     2>"$tmp/compare-bad.err"; then
  echo "malformed compare input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/compare-bad.out"
test -s "$tmp/compare-bad.err"

if $tool lifetime-escapes "$fixtures/lifetime-escapes.x" \
     "$fixtures/malformed.x" >"$tmp/lifetime-bad.out" \
     2>"$tmp/lifetime-bad.err"; then
  echo "malformed lifetime-escapes input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/lifetime-bad.out"
test -s "$tmp/lifetime-bad.err"

if $tool lifetime-escapes "$fixtures/lifetime-escapes.x" \
     "$fixtures/missing.x" >"$tmp/lifetime-missing.out" \
     2>"$tmp/lifetime-missing.err"; then
  echo "missing lifetime-escapes input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/lifetime-missing.out"
grep -q 'cannot read input file' "$tmp/lifetime-missing.err"

if $tool allocation-returns lifetime_scope_alias \
     "$fixtures/lifetime-escapes.x" \
     "$fixtures/malformed.x" >"$tmp/allocation-returns-bad.out" \
     2>"$tmp/allocation-returns-bad.err"; then
  echo "malformed allocation-returns input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/allocation-returns-bad.out"
test -s "$tmp/allocation-returns-bad.err"

if $tool allocation-returns lifetime_scope_alias "$fixtures/missing.x" \
     >"$tmp/allocation-returns-missing.out" \
     2>"$tmp/allocation-returns-missing.err"; then
  echo "missing allocation-returns input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/allocation-returns-missing.out"
grep -q 'cannot read input file' "$tmp/allocation-returns-missing.err"

if $tool graph "$fixtures/calls.x" "$fixtures/malformed.x" \
     >"$tmp/bad.out" 2>"$tmp/bad.err"; then
  echo "malformed input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/bad.out"
test -s "$tmp/bad.err"

if $tool graph "$fixtures/missing.x" >"$tmp/missing.out" \
     2>"$tmp/missing.err"; then
  echo "missing input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/missing.out"
grep -q 'cannot read input file' "$tmp/missing.err"

if $tool datasets "$tmp/datasets-malformed" \
     "$fixtures/dataset-src.x" "$fixtures/malformed.x" -- \
     "$fixtures/dataset-lib.x" >"$tmp/datasets-malformed.out" \
     2>"$tmp/datasets-malformed.err"; then
  echo "malformed dataset input unexpectedly succeeded" >&2
  exit 1
fi
test ! -e "$tmp/datasets-malformed"
test ! -s "$tmp/datasets-malformed.out"
test -s "$tmp/datasets-malformed.err"

if $tool datasets "$tmp/datasets-missing" \
     "$fixtures/dataset-src.x" -- "$fixtures/missing.x" \
     >"$tmp/datasets-missing.out" 2>"$tmp/datasets-missing.err"; then
  echo "missing dataset input unexpectedly succeeded" >&2
  exit 1
fi
test ! -e "$tmp/datasets-missing"
test ! -s "$tmp/datasets-missing.out"
grep -q 'cannot read input file' "$tmp/datasets-missing.err"

if $tool architecture "$fixtures/calls.x" "$fixtures/malformed.x" \
     >"$tmp/architecture-bad.out" 2>"$tmp/architecture-bad.err"; then
  echo "malformed architecture input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/architecture-bad.out"
test -s "$tmp/architecture-bad.err"

if $tool structure "$fixtures/calls.x" "$fixtures/missing.x" \
     >"$tmp/structure-missing.out" 2>"$tmp/structure-missing.err"; then
  echo "missing structure input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/structure-missing.out"
grep -q 'cannot read input file' "$tmp/structure-missing.err"

if $tool between "$fixtures/calls.x" "$fixtures/public-target.x" \
     "$fixtures/malformed.x" >"$tmp/between-bad.out" \
     2>"$tmp/between-bad.err"; then
  echo "malformed between input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/between-bad.out"
test -s "$tmp/between-bad.err"

if $tool between "$fixtures/calls.x" "$fixtures/public-target.x" \
     "$fixtures/missing.x" >"$tmp/between-missing.out" \
     2>"$tmp/between-missing.err"; then
  echo "missing between input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/between-missing.out"
grep -q 'cannot read input file' "$tmp/between-missing.err"

if $tool focus helper "$fixtures/calls.x" "$fixtures/malformed.x" \
     >"$tmp/focus-bad.out" 2>"$tmp/focus-bad.err"; then
  echo "malformed focus input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/focus-bad.out"
test -s "$tmp/focus-bad.err"

if $tool focus helper "$fixtures/missing.x" >"$tmp/focus-missing.out" \
     2>"$tmp/focus-missing.err"; then
  echo "missing focus input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/focus-missing.out"
grep -q 'cannot read input file' "$tmp/focus-missing.err"

if $tool field FieldOwner value "$fixtures/fields-a.x" \
     "$fixtures/malformed.x" >"$tmp/field-bad.out" \
     2>"$tmp/field-bad.err"; then
  echo "malformed field input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/field-bad.out"
test -s "$tmp/field-bad.err"

if $tool field FieldOwner value "$fixtures/missing.x" \
     >"$tmp/field-missing.out" 2>"$tmp/field-missing.err"; then
  echo "missing field input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/field-missing.out"
grep -q 'cannot read input file' "$tmp/field-missing.err"

if $tool sites site_target "$fixtures/sites-a.x" \
     "$fixtures/malformed.x" >"$tmp/sites-bad.out" \
     2>"$tmp/sites-bad.err"; then
  echo "malformed sites input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/sites-bad.out"
test -s "$tmp/sites-bad.err"

if $tool sites site_target "$fixtures/missing.x" \
     >"$tmp/sites-missing.out" 2>"$tmp/sites-missing.err"; then
  echo "missing sites input unexpectedly succeeded" >&2
  exit 1
fi
test ! -s "$tmp/sites-missing.out"
grep -q 'cannot read input file' "$tmp/sites-missing.err"
