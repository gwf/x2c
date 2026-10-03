#include "x2c.x"
macro Stmt $declare(Name $n,Expr $v){int $n=$v;}
macro Stmt $set_four(Name $out){{ $declare(v,4);$out=v; }}
int main(void){int v=7000;$set_four(v);printf("%d\n",v);return 0;}
