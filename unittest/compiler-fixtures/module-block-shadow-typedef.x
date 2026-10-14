/* A static typedef may not take the name of a module typedef, in either
   order of declaration. */
module { "module-block-shadow-typedef/member.x" }
module typedef int Number;
int main(void) => sizeof(Number);
