/* A static typedef may not take the name of a module object; objects,
   functions, and typedefs share one C namespace. */
module {
  "module-block-shadow-namespace/a.x",
  "module-block-shadow-namespace/b.x",
}
int main(void) => depth;
