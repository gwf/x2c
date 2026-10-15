/* A program's switch rule sees the integer switches the source writes,
   including one in a block that holds a String case label, but not the
   integer switch that lowering a String switch writes. */

#include "x2c.x"
#include "rewrite.x"

macro Stmt $int_switch(Expr $subject, Stmt $body) { switch ($subject) $body }

meta static int _counted_int(List type) {
  match (type) case %(int): return 1;
  return 0;
}

/* Counts each integer switch that runs. */
$rewrite($int_switch)
meta Code count_int_switch(Code node) {
  match (node) case %(switch (!set ?subject (expr ?type ?)) ?body):
    if (_counted_int(type))
      return $!{ { seen++; switch ($subject) $body } };
  return node;
}

static int seen = 0;

static int pick(String s, int k) {
  switch (s) {
    case "a":
      switch (k) { case 1: return 11; }
      return 10;
    case "b":
      if (k > 100) {
        case "c":
          switch (k) { case 2: return 32; }
          return 30;
      }
      return 20;
  }
  return 0;
}

int main(void) {
  int result = pick("a", 1) + pick("a", 0) + pick("b", 2) + pick("c", 2) +
               pick("c", 0) + pick("z", 0);
  printf("result=%d seen=%d\n", result, seen);
  return result == 103 && seen == 4 ? 0 : 1;
}
