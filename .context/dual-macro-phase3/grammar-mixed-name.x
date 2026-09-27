#include "x2c.x"
#include "meta.x"
macro Statement $named(Name $name, Expr $object) {
  int $name = 1;
  $name += $object.$name;
}
meta static Var name_view(Var value) {
  if (value is not <list>) return value;
  match(value) {
    case %((!or at src) ? ?body): return name_view(body);
    case %(literal *): return value;
  }
  Array parts=[];
  foreach(Var part,value.list()) parts.push(name_view(part));
  return parts.list_free();
}
meta static int name_probe_impl(List code) {
  fprintf(stderr,"Name code %s\n",name_view(code).repr().str());
  match(name_view(code).list()) {
    case %(block
      (declare ? (bindings (op = (bind ?name ?) ?)))
      (stmnt (expr ? (op += (expr ? (ident ?name))
        (expr ? (op . ?object (?member))))))): {
      return x2c_binding_spelling(name).equal(member.str());
    }
    default: return 0;
  }
}
macro Expression $name_probe(Statement $code) => $name_probe_impl($code);
struct Obj {int value; int other;};
int main(void) {
 struct Obj obj={2,3};
 int value=7;
 int hit=$name_probe({$named(value,obj);});
 int miss=$name_probe({int value=1;value+=obj.other;});
 int renamed=$name_probe({$named(other,obj);});
 int wrongref=$name_probe({int other=1;value+=obj.other;});
 printf("mixed Name %d %d %d %d\n",hit,miss,renamed,wrongref);
 return hit!=1||miss!=0||renamed!=1||wrongref!=0;
}
