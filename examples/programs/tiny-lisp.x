/* Copyright (c) 2026 Gary William Flake

   A tiny Lisp: quote, if, lambda, def, car, cdr, cons. Only () is false.
   Functions use dynamic scope; atoms are names, including numerals.
   x2c supplies Strings, Lists, Maps and match, but no Lisp machinery.

   Build: x2c build examples/programs/tiny-lisp.x --output /tmp/tiny-lisp
   Paste this into /tmp/tiny-lisp, then send EOF (Ctrl-D):

   (def join (lambda (a b)
     (if a (cons (car a) (join (cdr a) b)) b)))
   (def mul (lambda (a b)
     (if a (join b (mul (cdr a) b)) ())))
   (def fact (lambda (n)
     (if n (mul n (fact (cdr n))) '(x))))
   (fact '(x x x x))

   The last result is 4!: a list of 24 x's, with no numeric primitives.
*/

char *K[]={
  "quote", "if", "lambda", "def", "car", "cdr", "cons",
  " \t\r\n()';", " \t\r\n", "error\n"
};
String S(int i)=>String.new(K[i]);
Var F(void){fputs(K[9],stderr);exit(1);}
int c=' ';
void N(void){c=getchar();}
void W(void){for(;;)if(c!=EOF&&strchr(K[8],c))N();else if(c==';'){while(c!=EOF&&c!='\n')N();}else return;}
Var R(void){W();if(c==EOF||c==')')return F();if(c=='\''){N();return cons(S(0),cons(R(),NULL));}if(c=='('){N();Array a=$auto(%[]);for(W();c!=')';W())a.push(R());N();return a.list();}Buffer b=$auto(Buffer.new(0));do{b.write_char(c);N();}while(c!=EOF&&!strchr(K[7],c));return b.str();}
Var E(Var x,Map e){
  if(x is String){if(x in e)return e[x];return F();}
  if(x==%())return x;
  match(x){
    case %(?op ?v) if(op==S(0)):return v;
    case %(?op ?p ?a ?b) if(op==S(1)):return E(E(p,e)!=%()?a:b,e);
    case %(?op ?(List p) ?b) if(op==S(2)):return x;
    case %(?op ?(String n) ?v) if(op==S(3)):{e[n]=E(v,e);return n;}
    case %(?op ?a) if(op==S(4)||op==S(5)):{Var v=E(a,e);if(v is not List)return F();List l=v;if(op==S(5))return l.cdr();if(l)return l.car();return %();}
    case %(?op ?a ?b) if(op==S(6)):{Var v=E(a,e),w=E(b,e);if(w is not List)return F();return cons(v,w);}
    case %(?fn *args):match(E(fn,e)){
      case %(?op ?(List p) ?body) if(op==S(2)):{
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
