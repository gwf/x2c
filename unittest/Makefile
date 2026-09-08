SOURCE = .
BUILD = build

include ../etc/x2c.mk

X2CFLAGS +=
# This is needed because diagnostics.h is not part of libx2c.a.
CFLAGS += -iquote ../builds/0/src -Wno-invalid-pp-token

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
LDFLAGS += -rdynamic
$(BUILD)/test-logger.o: CFLAGS += -D_GNU_SOURCE
endif

TEST_OBJECTS = $(patsubst $(SOURCE)/%.x,$(BUILD)/%.o,$(X_FILES))
SUITE_OBJECTS = $(filter-out $(BUILD)/test-all.o,$(TEST_OBJECTS))

.PHONY: default all test sanitizer compiler-fixtures update-compiler-fixtures \
	benchmark-list iter-benchmark scope-benchmark match-capture-benchmark \
	scope-probes \
	error-probes exception-benchmark \
	varops-probes preprocessor-probes \
	cli-probes \
	symbol-snapshot-probes \
	header-cache-probes protocol-probes lisp-reader-benchmark clean clobber \
	expression-bodied-function-probes \
	FORCE

default: test-all compiler-fixtures scope-probes error-probes \
	varops-probes
all: test-all compiler-fixtures scope-probes error-probes \
	varops-probes

test-all: $(BUILD)/test-all.o $(SUITE_OBJECTS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS) $(LDLIBS)

test: test-all compiler-fixtures
	./test-all

sanitizer: test-all
	./probes/run-full-sanitizer.sh

scope-benchmark:
	./benchmarks/run-scope-hot-paths.sh

match-capture-benchmark:
	./benchmarks/run-match-capture-benchmark.sh

iter-benchmark:
	./benchmarks/run-iter-hot-paths.sh

scope-probes:
	./probes/run-scope-shutdown.sh

error-probes:
	./probes/run-error-floor.sh

varops-probes:
	./probes/run-varops-fatal.sh

preprocessor-probes:
	./probes/run-preprocessor-boundary.sh

cli-probes:
	./probes/run-cli-boundary.sh

symbol-snapshot-probes:
	./probes/run-symbol-snapshot.sh

header-cache-probes:
	./probes/run-header-cache.sh

protocol-probes:
	./probes/run-protocol-boundaries.sh

expression-bodied-function-probes:
	./probes/run-expression-bodied-functions.sh

compiler-fixtures: cli-probes preprocessor-probes symbol-snapshot-probes \
		header-cache-probes protocol-probes expression-bodied-function-probes
	./compiler-fixtures/run.sh check

update-compiler-fixtures:
	./compiler-fixtures/run.sh update

$(BUILD)/list-hot-paths: benchmarks/list-hot-paths.x FORCE | $(BUILD)
	$(X2C) translate $(X2CFLAGS) $<
	$(CC) $(CFLAGS) -o $@ $(BUILD)/list-hot-paths.c $(LDFLAGS) $(LDLIBS)

benchmark-list: $(BUILD)/list-hot-paths
	@for sample in 1 2 3 4 5; do \
		echo "sample,$$sample"; \
		./$(BUILD)/list-hot-paths; \
	done

$(BUILD)/lisp-reader-stream: benchmarks/lisp-reader-stream.x FORCE | $(BUILD)
	$(X2C) translate $(X2CFLAGS) $<
	$(CC) $(CFLAGS) -o $@ $(BUILD)/lisp-reader-stream.c \
		$(LDFLAGS) $(LDLIBS)

lisp-reader-benchmark: $(BUILD)/lisp-reader-stream
	@for sample in 1 2 3 4 5; do \
		echo "sample,$$sample"; \
		./$(BUILD)/lisp-reader-stream; \
	done

$(BUILD)/exception-hot-paths: benchmarks/exception-hot-paths.x FORCE | $(BUILD)
	$(X2C) translate $(X2CFLAGS) $<
	$(CC) $(CFLAGS) -o $@ $(BUILD)/exception-hot-paths.c $(LDFLAGS) $(LDLIBS)

exception-benchmark: $(BUILD)/exception-hot-paths
	@for sample in 1 2 3 4 5; do \
		echo "sample,$$sample"; \
		./$(BUILD)/exception-hot-paths; \
	done

FORCE:

clean:
	rm -rf test-all $(BUILD)

clobber: clean

$(BUILD)/test-all.o: $(BUILD)/test-support.h

# Compiler objects under test link through $^, not LDLIBS, so make
# sees them as prerequisites; builds/stage.mk owns building them and
# the top-level unittest target depends on x2c for freshness.
COMPILER_OBJECTS = ../builds/0/src/ast.o ../builds/0/src/diagnostics.o \
	../builds/0/src/report.o
test-all: $(COMPILER_OBJECTS)
