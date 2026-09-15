---
caption: from install to a running program
run: |
  curl -fsSL https://x2c-lang.dev/install.sh | sh
  export PATH="$HOME/.local/x2c/bin:$PATH"
  x2c run ~/.local/x2c/examples/foreach.x

  # Or from a source checkout
  ./x2c run examples/foreach.x

  # Strings, slicing, and interpolation
  ./x2c run examples/love/strings.x

  # Generate C arrays with compile-time Lisp
  ./x2c run examples/magic/compile-time.x
---
