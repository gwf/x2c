# Candidate adjudication

Answer these questions from current source and history:

1. What independent current purpose does this abstraction serve? If it owns a
   wanted capability, reject it before continuing.
2. Which operation produces each fact it stores, and which production code
   consumes it?
3. Is the fact already available from a canonical owner or translated back
   into an existing representation?
4. Is this only another delegation layer? Name any policy, transformation,
   lifetime, failure handling, or representation boundary it uniquely owns.
5. What identity, lifetime, ordering, diagnostics, side effects, concurrency,
   generated layout, or performance would change if it disappeared?
6. Are its tests independent behavior checks, or fixtures created solely for
   the mechanism?
7. What did the introducing plan, commit, and session actually authorize?
8. Did review become implementation, did the plan expand after implementation,
   or did successive edge cases create an unbounded completeness obligation?
9. Which existing owner preserves every intended behavior after removal?
10. What is the strongest case for keeping it?
11. What smallest probe would distinguish the removal hypothesis?

Do not confirm a deletion from naming, size, recency, low call count, or an old
rollback alone. Do not preserve machinery solely because it has extensive
tests or a detailed comment. Stop with `open` when the remaining question is
real and bounded.

The final presentation order is: the abstraction and why it lacks an
independent purpose, behavior preserved and its real owner, connected size,
evidence, strongest keep case, and disposition. A feature is never an
overengineering candidate merely because its implementation uses substantial
machinery or has low adoption.
