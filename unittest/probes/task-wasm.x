/* Optional: cooperative tasks and implicit main return through WebAssembly. */
#include "task.x"

int main(void) {
  for (int batch = 0; batch < 8; batch++) {
    Channel ready = auto Channel.new();
    Channel reply = auto Channel.new();
    Array cleanup = auto [0, 0];
    int caught = 0, original = 0;
    try Task.run([
      %!(void) => {
        defer cleanup[0] = cleanup[0].int() + 1;
        ready.receive();
        raise %(bad-arg (primary 47));
        return void;
      },
      %!(void) => {
        defer cleanup[1] = cleanup[1].int() + 1;
        ready.send(<ready>);
        return reply.receive();
      }
    ], NULL);
    catch %(join-fail (errors ?errors)): {
      caught++;
      foreach (List entry in errors.list())
        if (entry.assoc(<code>) == <bad-arg>)
          original = entry.assoc(<detail>).list().assoc(<primary>).int();
    }
    if (caught != 1 || original != 47 ||
        cleanup[0].int() != 1 || cleanup[1].int() != 1)
      return 1;
  }

  Channel gate = auto Channel.new();
  Array results = auto [];
  Task.run([
    %!(void) => gate.receive(),
    %!(void) => { gate.send(42); return 7; }
  ], %!(Var result) => { results.push(result); return void; });
  if (results.len() != 2 || results[0].int() != 7 || results[1].int() != 42)
    return 2;
  puts("Task.run WebAssembly probe passed");
}
