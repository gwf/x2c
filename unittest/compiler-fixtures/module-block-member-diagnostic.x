/* A diagnostic in a member names the member's file and line. */
int before(void) { return 1; }

module {
  "module-block-member-diagnostic/first.x",
  "module-block-member-diagnostic/second.x",
}

int after(void) { return 2; }
