class Account struct {
  String owner;
  int cents;
} *;

void Account.deposit(Account account, int cents) {
  account.cents += cents;
}
