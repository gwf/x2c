meta double not_compiler_target(double);
meta static double calls_missing_target(void) => not_compiler_target(1.0);

int main(void) { return $(calls_missing_target) == 1.0; }
