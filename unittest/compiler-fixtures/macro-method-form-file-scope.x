/* At file scope, an item that begins with a variable and whose postfix
   chain ends in `.name(arguments)` followed by a target applies the
   decorator `$T.name`, as `$T.name(variable, arguments) TARGET` does:
   before a function, stacked, before a `$` application, with an indexed
   receiver, and before a Unit target. The Expression form works in a
   file-scope initializer and a static initializer, and a template that
   expands at file scope uses the explicit spelling. */

#include "x2c.x"
#include "meta.x"

typedef struct App { int routes; } App;

App app;
App apps[2];
App *app_ptr = &app;

macro Decorator $App.route(Function $function, Expr $app, Expr $path) {
  printf("route %s\n", $path);
  @Code.body($function)
}

macro Decorator $App.unit(Unit $item, Expr $app) {
  $item
}

macro Expression $App.scaled(Expr $app, Expr $n) => $n * 10;

macro Decorator $traced(Function $function) {
  puts("traced");
  @Code.body($function)
}

app.route ("/x")
void handler(void) { puts("handler"); }

app.route ("/outer")
app.route ("/inner")
void stacked(void) { puts("stacked"); }

app.route ("/dollar")
$traced()
void dollar(void) { puts("dollar"); }

apps[1].route ("/index")
void indexed(void) { puts("indexed"); }

app_ptr[0].route ("/pointer")
void pointed(void) { puts("pointed"); }

app.unit()
int unit_value = 7;

int scaled = app.scaled(3);

macro Unit $page(Expr $a, Name $name) {
  $App.route($a, "/template")
  void $name(void) { puts("template"); }
}
$page(app, templated);

int main(void) {
  static int local_scaled = app.scaled(4);
  handler();
  stacked();
  dollar();
  indexed();
  pointed();
  templated();
  printf("%d %d %d\n", unit_value, scaled, local_scaled);
  return 0;
}
