static int earlier_private(void) => 1;
// lint: allow function-reading-order FI-4: retained teaching sequence
int later_public(void) => earlier_private();
