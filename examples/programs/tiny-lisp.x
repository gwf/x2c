/* Copyright (c) 2026 Gary William Flake

   A tiny Lisp: quote, if, lambda, def, car, cdr, cons, eq. Only () is false.
   Functions use dynamic scope; atoms are names, including numerals.
   x2c supplies Strings, Lists, Maps and match, but no Lisp machinery.

   Build: x2c build examples/programs/tiny-lisp.x --output /tmp/tiny-lisp
   Run: /tmp/tiny-lisp < examples/data/tiny-lisp.slp

   The demo defines unary, decimal, mul and fact in this Lisp, then computes:

   (decimal (fact (unary '(4))))                  ; (2 4)
   (decimal (mul (unary '(1 2)) (unary '(3))))     ; (3 6)

   Decimal digit lists make the input and output readable. Inside, 24 is
   still a list of 24 t's: there are no numeric primitives.
*/

Var F(void){fputs("error\n",stderr);exit(1);}
int c=' ';
void N(void){c=getchar();}
void W(void){for(;;)if(c!=EOF&&strchr(" \t\r\n",c))N();else if(c==';'){while(c!=EOF&&c!='\n')N();}else return;}
Var R(void){W();if(c==EOF||c==')')return F();if(c=='\''){N();return cons(%"quote",cons(R(),NULL));}if(c=='('){N();Array a=$auto(%[]);for(W();c!=')';W())a.push(R());N();return a.list();}Buffer b=$auto(Buffer.new(0));do{b.write_char(c);N();}while(c!=EOF&&!strchr(" \t\r\n()';",c));return b.str();}
Var E(Var x,Map e){
  if(x is String){if(x in e)return e[x];return F();}
  if(x==%())return x;
  match(x){
    case %("quote" ?v):return v;
    case %("if" ?p ?a ?b):return E(E(p,e)!=%()?a:b,e);
    case %("lambda" ?(List p) ?b):return x;
    case %("def" ?(String n) ?v):{e[n]=E(v,e);return n;}
    case %(?op ?a) if(op==%"car"||op==%"cdr"):{Var v=E(a,e);if(v is not List)return F();List l=v;if(op==%"cdr")return l.cdr();if(l)return l.car();return %();}
    case %("cons" ?a ?b):{Var v=E(a,e),w=E(b,e);if(w is not List)return F();return cons(v,w);}
    case %("eq" ?a ?b):{Var v=E(a,e),w=E(b,e);if(v==w)return %"t";return %();}
    case %(?fn *args):match(E(fn,e)){
      case %("lambda" ?(List p) ?body):{
        if(p.len()!=args.len())return F();
        Array v=$auto(%[]);foreach(Var a,args)v.push(E(a,e));
        Map d=$auto(e.copy());
        foreach(Var a,v){if(p.car() is not String)return F();d[p.car()]=a;p=p.cdr();}
        return E(body,d);
      }
    }
  }
  return F();
}
int main(void){$scope(){Map e=%{};for(W();c!=EOF;W())puts(E(R(),e).str());}return 0;}
