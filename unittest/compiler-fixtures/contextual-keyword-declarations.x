#include "x2c.x"

int try = 1;
int catch = 1;
int finally = 1;
int raise = 1;
int import = 1;
int protocol = 1;
int delegate = 1;
int associated = 1;
int threaded = 1;

struct Fields {
  int try;
  int catch;
  int finally;
  int raise;
  int import;
  int protocol;
  int delegate;
  int associated;
  int threaded;
};

static int parameters(int try, int catch, int finally, int raise,
                      int import, int protocol, int delegate,
                      int associated, int threaded) {
  return try + catch + finally + raise + import + protocol + delegate +
         associated + threaded;
}

int main(void) {
  int total = try + catch + finally + raise + import + protocol +
              delegate + associated + threaded;
  struct Fields fields = { 1, 1, 1, 1, 1, 1, 1, 1, 1 };
  total += fields.try + fields.catch + fields.finally + fields.raise +
           fields.import + fields.protocol + fields.delegate +
           fields.associated + fields.threaded;
  total += parameters(1, 1, 1, 1, 1, 1, 1, 1, 1);
  { typedef int try; try value = 1; total += value; }
  { typedef int catch; catch value = 1; total += value; }
  { typedef int finally; finally value = 1; total += value; }
  { typedef int raise; raise value = 1; total += value; }
  { typedef int import; import value = 1; total += value; }
  { typedef int protocol; protocol value = 1; total += value; }
  { typedef int delegate; delegate value = 1; total += value; }
  { typedef int associated; associated value = 1; total += value; }
  { typedef int threaded; threaded value = 1; total += value; }
  {
    int try = 1;
    int catch = 1;
    int finally = 1;
    int raise = 1;
    int import = 1;
    int protocol = 1;
    int delegate = 1;
    int associated = 1;
    int threaded = 1;
    total += try + catch + finally + raise + import + protocol +
             delegate + associated + threaded;
  }
  goto try;
  return 1;
  try: total++;
  goto catch;
  return 2;
  catch: total++;
  goto finally;
  return 3;
  finally: total++;
  goto raise;
  return 4;
  raise: total++;
  goto import;
  return 5;
  import: total++;
  goto protocol;
  return 6;
  protocol: total++;
  goto delegate;
  return 7;
  delegate: total++;
  goto associated;
  return 8;
  associated: total++;
  goto threaded;
  return 9;
  threaded: total++;
  printf("declarations %d\n", total);
  return total != 54;
}
