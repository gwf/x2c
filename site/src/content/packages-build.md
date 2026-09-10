```sh
# From your x2c checkout
make build-safe
./configure --packages raylib

# Build raylib and its chart example
make -C packages/raylib short-example

# Render the chart shown below
cd packages/raylib
./builds/climate-trends

# Result: builds/climate-trends.png
```
