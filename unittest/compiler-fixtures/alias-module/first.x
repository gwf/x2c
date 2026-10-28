module int counter = 2;
alias counter * 10 as scaled;
static alias mine to counter + 1;
module int first_value(void) { return mine; }
