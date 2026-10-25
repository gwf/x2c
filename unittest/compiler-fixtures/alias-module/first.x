module int counter = 2;
alias counter * 10 as scaled;
static alias counter + 1 as mine;
module int first_value(void) { return mine; }
