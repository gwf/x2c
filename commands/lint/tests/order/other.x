/* A second member exercises deterministic physical-file output. */
int member_public_leaf(void) => 1;
int member_public_caller(void) => member_public_leaf();
