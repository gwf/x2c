// Hero carousel panels. Each is one claim proved by code: a narrow bullet
// column and a wide code column, alternating sides. If a panel needs a
// paragraph it is not a panel; it belongs in one of the three sections below.
//
// side: "narrow-left" or "narrow-right".
// Keep bullets to four at six words or fewer, so the narrow column never
// outgrows the code column and the panel height stays fixed.

export const panels = [
  {
    id: "superset",
    label: "superset",
    title: "A strict superset of C.",
    bullets: [
      "C types, layouts, and ABI",
      "Any header, any library",
      "No wrapper, no marshalling",
      "Output is C you can read",
    ],
    code: `#include &lt;sqlite3.h&gt;

<span class="kw">static</span> <span class="type">int</span> row_count(sqlite3 *db, <span class="type">String</span> table) {
  sqlite3_stmt *stmt;
  <span class="type">String</span> sql = <span class="sigil">%</span><span class="str">"select count(*) from <span class="sigil">$</span>table"</span>;
  sqlite3_prepare_v2(db, sql.cstr(), <span class="num">-1</span>, &amp;stmt, NULL);
  <span class="kw">defer</span> sqlite3_finalize(stmt);
  <span class="kw">return</span> sqlite3_step(stmt) == SQLITE_ROW
    ? sqlite3_column_int(stmt, <span class="num">0</span>) : <span class="num">-1</span>;
}`,
  },
  {
    id: "sigils",
    label: "two characters",
    title: "It took two characters C left on the table.",
    bullets: [
      "% opens a literal",
      "The delimiter picks the grammar",
      "$ steps back out to C",
      "Binary % is still modulo",
    ],
    code: `<span class="type">List</span> row = <span class="sigil">%</span>(ready <span class="num">42</span>);
<span class="type">Map</span> totals = <span class="sigil">%</span>{};
<span class="type">Array</span> buffer = <span class="sigil">%</span>[];
<span class="type">String</span> greeting = <span class="sigil">%</span><span class="str">"hello world"</span>;

<span class="type">String</span> line = <span class="sigil">%</span><span class="str">"sold <span class="sigil">$</span>count units"</span>;
<span class="type">int</span> rest = a % b;`,
  },
  {
    id: "var",
    label: "Var",
    title: "One universal box, everywhere a value goes.",
    bullets: [
      "Local, parameter, argument, result",
      "Carries its own runtime kind",
      "The rest of the program stays C",
      "Native values stay native",
    ],
    code: `<span class="type">Var</span> answer(<span class="kw">void</span>) { <span class="kw">return</span> <span class="num">42</span>; }

<span class="kw">static void</span> use(<span class="type">Var</span> given) {
  <span class="type">Var</span> total = answer();
  total += given.integer();
  <span class="type">List</span> mixed = <span class="sigil">%</span>(<span class="sigil">$</span>total <span class="str">"units"</span> <span class="num">3.5</span>);
  printf(<span class="str">"%s\\n"</span>, mixed.repr());
}`,
  },
  {
    id: "macros",
    label: "macros",
    title: "The preprocessor C deserved.",
    bullets: [
      "Parameters are parsed types",
      "Runs after type analysis",
      "Distinct C types, no erasure",
      "Decorators know what follows",
    ],
    code: `<span class="kw">macro unit</span> <span class="sigil">$value.family</span>(<span class="kw">type</span> $box, <span class="kw">type</span> $item) =&gt; {
  $item $box.get($box box) { <span class="kw">return</span> box.value; }
}

<span class="sigil">$value.family</span>(IntValue, <span class="type">int</span>);
<span class="sigil">$value.family</span>(DoubleValue, <span class="type">double</span>);

<span class="type">int</span> port = <span class="sigil">$range</span>(<span class="num">1</span>, <span class="num">65535</span>) config.port;`,
  },
  {
    id: "batteries",
    label: "batteries",
    title: "The program that should never have needed Python.",
    bullets: [
      "Collections with literal forms",
      "Iteration is a protocol",
      "defer keeps cleanup in place",
      "Match the shape, not the index",
    ],
    code: `<span class="kw">static void</span> summarize(<span class="type">String</span> path) {
  <span class="type">File</span> input = path.open(<span class="str">"r"</span>);
  <span class="kw">defer</span> input.close();
  <span class="type">Map</span> totals = <span class="sigil">%</span>{};

  <span class="kw">for</span> (<span class="type">String</span> line <span class="kw">in</span> input) {
    <span class="type">String</span> (item, units) = line.split(<span class="str">" "</span>);
    totals[item.lower()] += units.long();
  }

  <span class="kw">for</span> (<span class="type">List</span> row <span class="kw">in</span> totals)
    printf(<span class="str">"%-16s %8ld\\n"</span>, row[<span class="num">0</span>], row[<span class="num">1</span>]);
}`,
  },
  {
    id: "lisp",
    label: "lisp",
    title: "A C that understands Lisp, and a Lisp that understands C.",
    bullets: [
      "Compile-time Lisp writes source",
      "Runtime Lisp decides policy",
      "Bindings derived from C types",
      "A native value comes back",
    ],
    code: `<span class="comment">// while translating</span>
<span class="kw">enum</span> Status { <span class="sigil">$</span>(x2c.ident <span class="str">"STATUS_READY"</span>) };

<span class="comment">// while running</span>
<span class="kw">static</span> <span class="type">int</span> allowed(<span class="type">Lisp</span> policy, <span class="type">int</span> value) {
  <span class="sigil">$lisp.bind</span>(policy, <span class="str">"clamp"</span>, clamp);
  <span class="kw">return</span> policy.eval(<span class="sigil">%</span>(clamp <span class="sigil">$</span>value <span class="num">0</span> <span class="num">8</span>));
}`,
  },
];

export default panels;
