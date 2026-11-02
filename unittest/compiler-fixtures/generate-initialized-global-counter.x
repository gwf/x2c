/* A public object whose initializer names a static object, used by
   `generate-initialized-global`. */
static int counter = 3;
int *current = &counter;
