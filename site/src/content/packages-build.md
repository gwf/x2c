```sh
# From your x2c checkout
make build-safe
./configure --packages raylib

make -C packages/raylib short-example
cd packages/raylib
./builds/climate-trends
# Result: builds/climate-trends.png
```
