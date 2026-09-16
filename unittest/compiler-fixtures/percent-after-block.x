#!/usr/bin/env -S x2c script
/* A statement starts after the `}` of a block or body, so a percent literal
   opens there. Each line of output comes from a literal that follows one. */

void List.show(List list) {
  printf("%s\n", list.repr());
}
%(after function body).show();

void String.show(String text) {
  printf("%s\n", text);
}

void SymbolSet.show(SymbolSet set) {
  printf("SymbolSet of %zu\n", set.len());
}

String name = %"block";
{
  name = %"nested block";
}
%"after $name".show();

foreach (String word, %("one" "two")) {
  printf("%s\n", word);
}
%(after foreach).show();

if (name) {
  name = %"if";
}
else {
  name = %"else";
}
%(after else).show();
%[after, $name].repr().show();

while (!name) {
}
%(after while).show();

$scope() {
  name.len();
}
%(after decorator).show();

with name {
  _.show();
}
%(after with).show();

switch (name.len()) {
  default: {
    name = %"case";
  }
  %"after $name block".show();
  %(after case block).show();
}
%<<after switch>>.show();
%(after switch).show();
