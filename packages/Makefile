PACKAGES := pcre2 yyjson termbox2 raylib libcurl libuv blis cstar
# The packages the root `make packages-check` builds and runs.
CHECKED_PACKAGES := pcre2 yyjson libcurl termbox2 blis libuv raylib

.PHONY: test-deps cache-path prepare-checked \
	$(addprefix prepare-,$(PACKAGES))

test-deps:
	python3 tools/test-deps.py

cache-path:
	@python3 tools/deps.py path pcre2/dependency.json cache

prepare-checked: $(addprefix prepare-,$(CHECKED_PACKAGES))

$(addprefix prepare-,$(PACKAGES)): prepare-%:
	$(MAKE) -C $* prepare
