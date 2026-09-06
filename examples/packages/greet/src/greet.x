/*  greet.x -- the package the import example consumes.

    A package needs no manifest and no export list: everything above
    `#pragma private` reaches an importing unit as `greet__*`.
*/

typedef struct GreetingData {
  String subject;
  int count;
} *Greeting;

Greeting Greeting.new(String subject);
String Greeting.line(Greeting greeting);
String repeat(String text, int times);

#pragma private

Greeting Greeting.new(String subject) {
  Greeting greeting = Scope.malloc(sizeof(struct GreetingData));
  greeting.subject = subject;
  greeting.count = 0;
  return greeting;
}

String Greeting.line(Greeting greeting) {
  greeting.count++;
  return %"hello, ${greeting.subject} (${greeting.count})";
}

String repeat(String text, int times) {
  Array parts = %[];
  for (int i = 0; i < times; i++) parts.push(text);
  String joined = %" ".join(parts.list_free());
  return joined;
}
