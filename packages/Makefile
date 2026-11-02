# The packages `make packages` and `make packages-check` cover.
# release-validation excludes torch and the notes application. Each package's own `check` target
# names what checking it runs; agents/releasing.md lists what releases ship.
PACKAGES := pcre2 yyjson sqlite libcurl termbox2 blis libuv raylib torch \
  autodiff

.PHONY: list examples check prepare test-deps cache-path \
	$(addprefix prepare-,$(PACKAGES))

list:
	@echo $(PACKAGES)

# Build every package's applications, or check every package, in order.
examples check:
	@set -e; for package in $(PACKAGES); do $(MAKE) -C $$package $@; done

test-deps:
	python3 tools/test-deps.py

cache-path:
	@python3 tools/deps.py path pcre2/dependency.json cache

prepare: $(addprefix prepare-,$(PACKAGES))

$(addprefix prepare-,$(PACKAGES)): prepare-%:
	$(MAKE) -C $* prepare
