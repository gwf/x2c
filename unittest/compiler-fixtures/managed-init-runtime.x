#include "x2c.x"
#include "lisp.x"
#include "machine.x"
#include "typed-array.x"
#include "typed-map.x"
int main(void) {
  $scope() {
    Array array = $auto(%[]);
    Block block = $auto(Block.new(sizeof(int)));
    Bytes bytes = $auto(Bytes.new(sizeof(int)));
    Buffer buffer = $auto(Buffer.new(0));
    Map map = $auto(%{});
    Mutex mutex = $auto(Mutex.new());
    Scope scope = $auto(Scope.new());
    File input = $auto(File.open("/dev/null", "r"));
    Lisp lisp = $auto(Lisp.new_bare());
    MachineBuilder builder = $auto(MachineBuilder.new());
    ArrayInt ints = $auto(ArrayInt.new());
    MapStringInt counts = $auto(MapStringInt.new());
    array.push(1);
    ints.push(2);
    counts["one"] = 1;
    printf("%d %d %d\n", array[0].int(), ints[0], counts["one"]);
    {
      Context context = $auto(Context.open());
      Array local = $auto(%[]);
      local.push(3);
    }
  }
  return 0;
}
