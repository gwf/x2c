#include "x2c.x"
#include <stdint.h>
#include <stdio.h>

typedef Var Dynamic;
typedef Dynamic DynamicAgain;
typedef int NativeInt;
typedef NativeInt NativeIntAlias;
typedef NativeIntAlias *NativeIntPointer;
typedef NativeIntPointer *NativeIntDoublePointer;

typedef struct IsWidgetData { int value; } *IsWidget;
typedef IsWidget IsWidgetAlias;

Var IsWidget.var(IsWidget widget);
IsWidget Var.iswidget(Var value);

static int calls;
static int tag_calls;

static Var next_value(void) {
  calls++;
  return 7;
}


static Symbol next_tag(void) {
  tag_calls++;
  return <i32>;
}


static Var call_or_void(int (*function)(void)) {
  if (function) return function();
  return void;
}


static int symbol_shadows_type(Var value) {
  Symbol NativeInt = <i32>;
  return value is NativeInt;
}

static int custom_visible_before_protocol(Var value) {
  return value is IsWidgetAlias;
}

Var IsWidget.var(IsWidget widget) {
  return Var.new(<iswidget>, widget);
}

IsWidget Var.iswidget(Var value) {
  return value.pointer();
}

protocol Var(IsWidget);

int main(void) {
  x2c_register_type(%"iswidget");
  int integer = 7, *pointer = &integer, **double_pointer = &pointer;
  Var scalar = integer;
  Dynamic alias = scalar;
  DynamicAgain nested_alias = alias;
  Var signed_byte = (signed char) -1;
  Var unsigned_byte = (unsigned char) 255;
  Var unsigned_value = (unsigned) 7;
  Var wide_integer = (long long) 7;
  Var wide_unsigned = (unsigned long long) 7;
  Var floating = (float) 1.5;
  Var wide_floating = (long double) 1.5;
  Var system_integer = (int32_t) 7;
  Var list = %();
  Var string = %"";
  Var symbol = <fixture>;
  Var pointer_value = pointer;
  Var double_pointer_value = double_pointer;
  Var null_value = (void *) NULL;
  Var absent = void;
  IsWidget widget = Scope.malloc(sizeof(struct IsWidgetData));
  widget.value = 9;
  IsWidgetAlias widget_alias = widget;
  Var custom = widget_alias;
  Symbol scalar_tag = <i32>;
  int is = 1;

  int ok =
    nested_alias is int &&
    scalar is i32 && scalar is int32_t && scalar is NativeIntAlias &&
    scalar is const int &&
    signed_byte is char && signed_byte is signed char &&
    signed_byte is not u8 && unsigned_byte is u8 &&
    unsigned_value is unsigned && unsigned_value is not int &&
    wide_integer is long long && wide_integer is not long &&
    wide_unsigned is unsigned long long && wide_unsigned is not unsigned long &&
    floating is float && floating is not double &&
    wide_floating is long double &&
    system_integer is int &&
    list is List && string is String && symbol is Symbol &&
    scalar is not Var &&
    pointer_value is (int *) &&
    pointer_value is NativeIntPointer &&
    double_pointer_value is (int **) &&
    double_pointer_value is NativeIntDoublePointer &&
    null_value is (void *) && null_value is not void &&
    absent is void && absent is not (void *) &&
    custom_visible_before_protocol(custom) && custom is IsWidget &&
    custom is IsWidgetAlias &&
    scalar is int == 1 && (scalar is int || scalar is u8) &&
    scalar is not double && next_value() is int && calls == 1 &&
    call_or_void(NULL) is void &&
    symbol_shadows_type(scalar) &&
    scalar is <i32> && scalar is scalar_tag &&
    scalar is next_tag() && tag_calls == 1 &&
    scalar is not <not-a-type> &&
    scalar.is(<i32>) && is;

  printf("%d %d %d\n", ok, calls, tag_calls);
  return ok ? 0 : 1;
}
