#include <assert.h>

class Count int;
class IntPointer int *;
class Points Array;
class Point { int x; int y; };
class Notebook struct { int scale; Points readings; } *;

void Notebook.init(Notebook notebook) {
  notebook.scale = 1;
  notebook.readings = Points.new();
}

void Notebook.record(Notebook notebook, Point point) {
  notebook.readings.push(Point.new(
    point.x * notebook.scale, point.y * notebook.scale));
}

void Notebook.free(Notebook notebook) {
  notebook.readings.free();
  Scope.free(notebook);
}

String Notebook.repr(Notebook notebook) {
  size_t count = notebook.readings.len();
  return %"Notebook($count readings, scale=${notebook.scale})";
}

int main(void) {
  $scope() {
    Scope samples = $auto(Scope.new());
    Notebook notebook = $auto(Notebook.new());
    IntPointer step = $auto(IntPointer.new(2));
    Mutex mutex = $auto(Mutex.new());
    Count count = Count.new(3);

    for (int i = 0; i < count; i++) $scope() {
      Point point = Point.new(i, i * (*step));
      // The copied Points must outlive this iteration's temporary region.
      $scope(&samples) $lock(mutex) $let(notebook.scale, 2) {
        notebook.record(point);
      }
    }

    assert(notebook.scale == 1);
    printf("%s\n", notebook.readings.repr());
    Array display = $auto(%[$notebook]);
    printf("%s\n", display.repr());

    Point point = Point.new(1, 2);
    Var boxed = point;
    point.x = 99;
    Point copy = boxed;
    Map labels = $auto(%{});
    labels[boxed] = "same point";
    Var lookup = Point.new(1, 2);
    assert(boxed == lookup && boxed.hash() == lookup.hash());
    printf("copy: %d,%d; key: %s\n", copy.x, copy.y, labels[lookup].str());
  }
  return 0;
}
