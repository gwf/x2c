/* A file's static object defined again without `static` is a second
   definition of the same object. */
module {
  "module-static-redefinition/first.x",
}

int main(void) { return first_value(); }
