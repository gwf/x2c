# check.sh reads the exported BUILD_CFLAGS, BUILD_LDFLAGS, and BUILD_JOBS.
include ../etc/make-command.mk
include ../etc/build-config.mk

.PHONY: default check update list clean

default: check

check:
	./check.sh check

update:
	./check.sh update

list:
	@awk -F '|' '!/^#/ && NF { printf "%-28s %-16s %s\n", $$1, $$2, $$3 }' \
		manifest.txt

clean:
	rm -rf build packages/*/builds
