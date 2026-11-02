# Stops a Map benchmark runner unless the x2c build mode is optimize.
# Source this file after setting root. Make exports BUILD_MODE to the bm-map
# recipes; a runner started by hand reads the mode the next build uses,
# etc/build-mode.local and then etc/build-mode.
if [ "${BUILD_MODE:-$(cat "$root/etc/build-mode.local" 2>/dev/null ||
  cat "$root/etc/build-mode" 2>/dev/null)}" != optimize ]; then
  echo "the Map benchmarks require the optimized x2c build mode" >&2
  echo "run 'make config-optimize', clean, and rebuild before benchmarking" >&2
  exit 2
fi
