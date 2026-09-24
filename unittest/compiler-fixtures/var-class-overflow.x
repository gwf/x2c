/* A class spends a Var row only when a value of it is first boxed, and a
   process can box any number of classes: the first 30 boxed get direct rows,
   later heap classes box through a cell (row 30), and later records carry
   their descriptor in front of the copy (row 31). */
#include "x2c.x"

class R00 { int x; };
class R01 { int x; };
class R02 { int x; };
class R03 { int x; };
class R04 { int x; };
class R05 { int x; };
class R06 { int x; };
class R07 { int x; };
class R08 { int x; };
class R09 { int x; };
class R10 { int x; };
class R11 { int x; };
class R12 { int x; };
class R13 { int x; };
class R14 { int x; };
class R15 { int x; };
class R16 { int x; };
class R17 { int x; };
class R18 { int x; };
class R19 { int x; };
class R20 { int x; };
class R21 { int x; };
class R22 { int x; };
class R23 { int x; };
class R24 { int x; };
class R25 { int x; };
class R26 { int x; };
class R27 { int x; };
class R28 { int x; };
class R29 { int x; };
class R30 { int x; };
class R31 { int x; };
class R32 { int x; };
class R33 { int x; };
class R34 { int x; };
class R35 { int x; };
class R36 { int x; };
class R37 { int x; };
class R38 { int x; };
class R39 { int x; };
class H00 struct { int x; } *;
class H01 struct { int x; } *;
class H02 struct { int x; } *;
class H03 struct { int x; } *;
class H04 struct { int x; } *;
class H05 struct { int x; } *;
class H06 struct { int x; } *;
class H07 struct { int x; } *;
class H08 struct { int x; } *;
class H09 struct { int x; } *;
class H10 struct { int x; } *;
class H11 struct { int x; } *;
class H12 struct { int x; } *;
class H13 struct { int x; } *;
class H14 struct { int x; } *;
class H15 struct { int x; } *;
class H16 struct { int x; } *;
class H17 struct { int x; } *;
class H18 struct { int x; } *;
class H19 struct { int x; } *;
class H20 struct { int x; } *;
class H21 struct { int x; } *;
class H22 struct { int x; } *;
class H23 struct { int x; } *;
class H24 struct { int x; } *;
class H25 struct { int x; } *;
class H26 struct { int x; } *;
class H27 struct { int x; } *;
class H28 struct { int x; } *;
class H29 struct { int x; } *;
class H30 struct { int x; } *;
class H31 struct { int x; } *;
class H32 struct { int x; } *;
class H33 struct { int x; } *;
class H34 struct { int x; } *;
class H35 struct { int x; } *;
class H36 struct { int x; } *;
class H37 struct { int x; } *;
class H38 struct { int x; } *;
class H39 struct { int x; } *;
class Unboxed struct { int x; } *;

int main(void) {
  // Eighty-one classes are declared; the first box still takes row 0.
  H39 last = H39.new(39);
  Var first = last;
  printf("first row %d\n", first.custom_descriptor_index());
  Array heaps = [], records = [];
  heaps.push(H00.new(0)), records.push(R00.new(0));
  heaps.push(H01.new(1)), records.push(R01.new(1));
  heaps.push(H02.new(2)), records.push(R02.new(2));
  heaps.push(H03.new(3)), records.push(R03.new(3));
  heaps.push(H04.new(4)), records.push(R04.new(4));
  heaps.push(H05.new(5)), records.push(R05.new(5));
  heaps.push(H06.new(6)), records.push(R06.new(6));
  heaps.push(H07.new(7)), records.push(R07.new(7));
  heaps.push(H08.new(8)), records.push(R08.new(8));
  heaps.push(H09.new(9)), records.push(R09.new(9));
  heaps.push(H10.new(10)), records.push(R10.new(10));
  heaps.push(H11.new(11)), records.push(R11.new(11));
  heaps.push(H12.new(12)), records.push(R12.new(12));
  heaps.push(H13.new(13)), records.push(R13.new(13));
  heaps.push(H14.new(14)), records.push(R14.new(14));
  heaps.push(H15.new(15)), records.push(R15.new(15));
  heaps.push(H16.new(16)), records.push(R16.new(16));
  heaps.push(H17.new(17)), records.push(R17.new(17));
  heaps.push(H18.new(18)), records.push(R18.new(18));
  heaps.push(H19.new(19)), records.push(R19.new(19));
  heaps.push(H20.new(20)), records.push(R20.new(20));
  heaps.push(H21.new(21)), records.push(R21.new(21));
  heaps.push(H22.new(22)), records.push(R22.new(22));
  heaps.push(H23.new(23)), records.push(R23.new(23));
  heaps.push(H24.new(24)), records.push(R24.new(24));
  heaps.push(H25.new(25)), records.push(R25.new(25));
  heaps.push(H26.new(26)), records.push(R26.new(26));
  heaps.push(H27.new(27)), records.push(R27.new(27));
  heaps.push(H28.new(28)), records.push(R28.new(28));
  heaps.push(H29.new(29)), records.push(R29.new(29));
  heaps.push(H30.new(30)), records.push(R30.new(30));
  heaps.push(H31.new(31)), records.push(R31.new(31));
  heaps.push(H32.new(32)), records.push(R32.new(32));
  heaps.push(H33.new(33)), records.push(R33.new(33));
  heaps.push(H34.new(34)), records.push(R34.new(34));
  heaps.push(H35.new(35)), records.push(R35.new(35));
  heaps.push(H36.new(36)), records.push(R36.new(36));
  heaps.push(H37.new(37)), records.push(R37.new(37));
  heaps.push(H38.new(38)), records.push(R38.new(38));
  heaps.push(H39.new(39)), records.push(R39.new(39));
  int ok = 1;
  for (int i = 0; i < 40; i++) {
    Var heap = heaps[i], record = records[i];
    Var twin = Var.new(heap.tag(), heap.pointer());
    ok = ok && heap.same(twin) && heap == twin && heap.hash() == twin.hash();
    ok = ok && (record == R00.new(0)) == (i == 0);
    for (int j = 0; j < i; j++)
      ok = ok && heap.tag() != heaps[j].tag() &&
           record.tag() != records[j].tag();
  }
  ok = ok && heaps[0] is H00 && ((H00) heaps[0]).x == 0;
  ok = ok && heaps[38] is H38 && ((H38) heaps[38]).x == 38;
  ok = ok && records[0] is R00 && ((R00) records[0]).x == 0;
  ok = ok && records[39] is R39 && ((R39) records[39]).x == 39;
  ok = ok && !(heaps[38] is H37) && !(records[39] is R38);
  ok = ok && !(heaps[38] is Unboxed) && (H39) first == last;
  // An overflow heap box outlives the Scope it was made in.
  H38 object = heaps[38];
  Var inner;
  $scope() {
    inner = object;
  }
  Var outer = object;
  ok = ok && inner.same(outer) && inner.u64 == outer.u64;
  ok = ok && inner is H38 && ((H38) inner).x == 38;
  printf("checks %s\n", ok ? "pass" : "fail");
  printf("rows %d %d %d %d\n", heaps[0].custom_descriptor_index(),
         heaps[38].custom_descriptor_index(),
         records[0].custom_descriptor_index(),
         records[39].custom_descriptor_index());
  printf("%s %s\n", heaps[38].repr(), records[39].repr());
  return 0;
}
