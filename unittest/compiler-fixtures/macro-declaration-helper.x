#pragma once

macro Stmt $declare_list(Name $name) {
  List $name = cons(String_var(String_new("abc")),
    cons(String_var(String_new("de")), NULL));
}
