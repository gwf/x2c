# Typed pattern composition spike

`typed.x` derives patterns from ordinary expression macros. A typed quotation
constrains the complete expression's type without constructing its AST:

```x2c
Macro sum = $sum;
List shape = sum.pattern(%(?left ?right));
return $!int{ $shape };
```

The second example composes an integer negation pattern as the left operand
of addition. `!and` is an existing Match operator, not an AST constructor.
The outer pattern must retain that explicit recognition operand unchanged.
Four added lines in `lib/macro-value.x` preserve it and unwrap its expression
hole. Before the change, the nested operator was quoted twice and the integer
type constraint was discarded. This is an exact structural type constraint;
it does not request an implicit conversion or subtype relation.

Expected output:

```text
1 0 0
1 0 0
```

The first row distinguishes integer addition, floating-point addition, and
integer multiplication. The second distinguishes integer negation on the left,
floating-point negation on the left, and an unnegated left operand. The right
operand can be double in the positive nested case: the constraint belongs to
the left operand, not the complete sum.

This demonstrates pattern construction and compile-time recognition. It does
not by itself register an automatic rewrite. The dispatch experiment owns
that separate connection. No new syntax, AST constructors, or caller-managed
pattern cursors are introduced.
