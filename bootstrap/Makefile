
###############################################################################

include ../etc/make-command.mk
include ../etc/build-config.mk
FLAGS = $(BUILD_CFLAGS)

all: FORCE
	$(PARALLEL_MAKE) -C lib FLAGS="$(FLAGS)"
	$(PARALLEL_MAKE) -C src FLAGS="$(FLAGS)"

realclean clean: FORCE
	$(MAKE) -C lib $@
	$(MAKE) -C src $@

FORCE:

###############################################################################
