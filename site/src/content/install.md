---
caption: from install to a running program
run: |
  curl -fsSL https://x2c-lang.dev/install.sh | sh
  export PATH="$HOME/.local/x2c/bin:$PATH"
  x2c run ~/.local/x2c/examples/foreach.x
---
