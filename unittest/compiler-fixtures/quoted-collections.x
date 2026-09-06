#include "x2c.x"

macro Entry $fixture.row() => {
  "macro": 12
}

typedef struct Pair {
  int value;
} Pair;

enum Choice {
  chosen = 23
};

static int bump(int *value) => ++*value;

int main(void) {
  int count = 7, evals = 0, indexed[] = {10, 11};
  Pair pair = { .value = 22 };
  List list_nested = %([array, $count] {map: $count});
  Array values = %[
    ready,
    VeryLongIdentifierName,
    "text",
    [nested, $count],
    {kind: widget},
    ${count * 2},
    -3,
    'q',
    colon\:name,
    right\],
    right\},
    <"">,
    <1>,
    <+>,
    1.5,
    "line one
line two",
    "\$count",
    ${"c text"},
    ${pair.value},
    ${indexed[1]},
    ${bump(&evals)},
    ${NULL},
    ${chosen},
    ${((Pair) { .value = 24 }).value},
    ${(count, count + 3)},
    ${$(+ 20 5)}
  ];
  Map config = %{
    name: "x2c",
    runtime: $count,
    computed: ${count + 2},
    nested: {depth: 8},
    values: [1, $count],
    ${$fixture.row()}
  };

  if (list_nested[0].array()[1].integer() != 7 ||
      list_nested[1].map()[<map>].integer() != 7)
    return 1;
  if (values[0].str() != %"ready") return 2;
  if (values[1].str() != %"VeryLongIdentifierName") return 3;
  if (values[2].string() != %"text") return 4;
  if (values[3].array()[1].integer() != 7) return 5;
  if (values[4].map()[<kind>].str() != %"widget") return 6;
  if (values[5].integer() != 14 || values[6].integer() != -3) return 7;
  if (values[7].char() != 'q') return 8;
  if (values[8].str() != %"colon:name" || values[9].str() != %"right]")
    return 9;
  if (values[10].str() != %"right}" || values[11].symbol() != <""> ||
      values[12].symbol() != <1> || values[13].symbol() != <+>)
    return 10;
  if (values[14].floating() != 1.5 ||
      values[15].string() != %"line one\nline two" ||
      values[16].string() != %"\$count" ||
      values[17].string() != %"c text")
    return 11;
  if (values[18].integer() != 22 || values[19].integer() != 11 ||
      values[20].integer() != 1 || evals != 1)
    return 12;
  if (!values[21].is_null() || values[22].integer() != 23 ||
      values[23].integer() != 24 || values[24].integer() != 10 ||
      values[25].integer() != 25)
    return 13;
  if (config[<name>].string() != %"x2c") return 14;
  if (config[<runtime>].integer() != 7) return 15;
  if (config[<computed>].integer() != 9) return 16;
  if (config[<nested>].map()[<depth>].integer() != 8) return 17;
  if (config[<values>].array()[1].integer() != 7) return 18;
  if (config["macro"].integer() != 12) return 19;
  printf("quoted collections ok\n");
  return 0;
}
