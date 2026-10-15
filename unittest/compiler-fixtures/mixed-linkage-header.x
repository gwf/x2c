/* Each declarator keeps its own visibility after a private definition. */
static int hidden(void) { return 7; }
int hidden(void), public_fn(void);
