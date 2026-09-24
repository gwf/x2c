# Candidate adjudication

Answer these questions from current source and history:

1. What exact user-visible or developer-visible capability would disappear?
   Write one minimal example that works today.
2. Which operation produces each fact it stores, and which production code
   consumes it?
3. Is the fact already available from a canonical owner or translated back
   into an existing representation?
4. What identity, lifetime, ordering, diagnostics, side effects, concurrency,
   generated layout, or performance would change if it disappeared?
5. Are its tests independent behavior checks, or fixtures created solely for
   the mechanism?
6. What did the introducing plan, commit, and session actually authorize?
7. Did review become implementation, did the plan expand after implementation,
   or did successive edge cases create an unbounded completeness obligation?
8. Would removal preserve behavior or deliberately narrow the product?
9. What is the strongest case for keeping it?
10. What smallest probe would distinguish the removal hypothesis?

Do not confirm a deletion from naming, size, recency, low call count, or an old
rollback alone. Do not preserve machinery solely because it has extensive
tests or a detailed comment. Stop with `open` when the remaining question is
real and bounded.

The final presentation order is: capability and example, consequence of
removal, evidence of current use, connected size, architectural concern,
strongest keep case, and disposition. A low-adoption feature is not confirmed
overengineering until Gary decides the feature itself is unwanted or the same
behavior can be preserved without the machinery.
