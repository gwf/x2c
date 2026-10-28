.DEFAULT_GOAL := x2c.x

SHELL := /bin/sh

# Optional x2c system modules are built with the runtime but require an
# explicit source include. They are not part of the implicit standard prelude.
OPTIONAL_SOURCES := net.x http.x args.x derive.x test.x datum.x datum-reader.x diff.x digest.x json.x \
                    list-selectors.x meta.x type.x path.x process.x regex.x \
                    rewrite.x scripting.x substring.x substring-map.x \
                    typed-array.x typed-list.x typed-map.x \
                    var-ledger.x lisp-targets/lisp-targets.x compiler-meta.x \
                    lisp-bindings.x \
                    cleanup.x error-macros.x error-private.x integer-ops.x \
                    native-scalar-types.x private-keywords.x system-macros.x \
                    var-adapters.x var-tags.x
SOURCES := $(sort $(filter-out x2c.x $(OPTIONAL_SOURCES),$(patsubst ../lib/%,%,$(shell ../tools/sources.sh --root .. --area lib))))

.PHONY: FORCE
FORCE:

# Regenerate x2c.x to stay in sync with the directory contents, but only
# if it has changed. This avoids unnecessary rebuilds of everything.
x2c.x: FORCE
	@{ \
		tmp="$@.$$$$"; \
		{ echo '#pragma once'; \
		for f in $(SOURCES); do \
			echo "#include \"$$f\""; \
		done; \
		} > "$$tmp"; \
		if [ -e "$@" ] && cmp -s "$$tmp" "$@"; then \
		rm -f "$$tmp"; \
		else \
		mv "$$tmp" "$@"; \
		fi; \
	}
