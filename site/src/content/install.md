---
caption: from source to a running program
---

```sh
git clone https://github.com/gwf/x2c.git
cd x2c
make build-safe

./x2c run examples/foreach.x

# Strings, slicing, and interpolation
./x2c run examples/love/strings.x

# Generate C arrays with compile-time Lisp
./x2c run examples/magic/compile-time.x
```
