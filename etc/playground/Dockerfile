# Build from the repository root: docker build -f etc/playground/Dockerfile -t x2c-playground .
FROM emscripten/emsdk:6.0.13
WORKDIR /opt/x2c
COPY Makefile configure LICENSE NOTICE THIRD_PARTY.md ./
COPY LICENSES/ ./LICENSES/
COPY builds/Makefile builds/stage.mk ./builds/
COPY bin/Makefile ./bin/
COPY bootstrap/ ./bootstrap/
COPY src/ ./src/
COPY lib/ ./lib/
COPY include/ ./include/
COPY etc/ ./etc/
COPY tools/ ./tools/
COPY commands/manifest.txt ./commands/
COPY examples/power/exceptions.x ./examples/power/
COPY examples/data/power-exceptions/ ./examples/data/power-exceptions/
RUN make build-safe && make wasm-runtime \
    && WASM_LDFLAGS='--embed-file /opt/x2c/examples/data/power-exceptions@examples/data/power-exceptions' \
       tools/wasm-build examples/power/exceptions.x /tmp/warm \
    && chmod -R a+rX /opt/x2c /emsdk \
    && chmod -R a-w /opt/x2c
ENV HOME=/tmp EM_CACHE=/emsdk/upstream/emscripten/cache
USER 65534:65534
WORKDIR /tmp
ENTRYPOINT ["node", "/opt/x2c/etc/playground/compile.mjs"]
