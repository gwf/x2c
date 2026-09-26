meta double not_compiler_target(double);
$(import "comptime-declines-native-meta-missing.xmacro")

int main(void) { return $(calls_missing_target) == 1.0; }
