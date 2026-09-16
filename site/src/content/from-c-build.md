```sh
# From your x2c checkout
./x2c run examples/c/account-c.x
./x2c run examples/c/account-foreach.x

# Keep main in C and link the x2c class
./x2c build --output /tmp/account \
  examples/c/main.c examples/c/account.x
/tmp/account
```
