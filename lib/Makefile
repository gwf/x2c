.DEFAULT_GOAL := x2c.x

SHELL := /bin/sh

# Optional x2c system modules are built with the runtime but require an
# explicit source include. They are not part of the implicit standard prelude.
OPTIONAL_SOURCES := autodiff.x list-selectors.x match-recursive.x \
                    typed-array.x typed-list.x typed-map.x
SOURCES := $(sort $(filter-out x2c.x $(OPTIONAL_SOURCES),$(wildcard *.x)))

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
