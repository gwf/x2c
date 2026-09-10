---
caption: from source to a running program
run: |
  ./x2c run examples/foreach.x

  # Strings, slicing, and interpolation
  ./x2c run examples/love/strings.x

  # Generate C arrays with compile-time Lisp
  ./x2c run examples/magic/compile-time.x
---
