###############################################################################

CFLAGS   =	-iquote . -iquote ../lib $(FLAGS)
LDFLAGS  =	-lm
SRCS     =  $(wildcard *.c)
OBJS     =  $(SRCS:%.c=%.o)
# A native module binds to the compiler's own runtime, so the compiler links
# every runtime object but the Lisp interpreter and its target table, and a
# Linux executable exports its functions only when asked.
RUNTIME  =  $(filter-out ../lib/lisp.o ../lib/lisp-targets.o, \
	      $(patsubst %.c,%.o,$(wildcard ../lib/*.c)))
UNAME_S  := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
LDFLAGS  +=	-rdynamic
endif

.DELETE_ON_ERROR:

../../bin/x2c: x2c install

x2c: $(OBJS) ../lib/libx2c.a
	$(CC) -o $@ $(OBJS) $(RUNTIME) $(LDFLAGS)
	rm -f ../../bin/x2c-bootstrap
	cp x2c ../../bin/x2c-bootstrap

install:
	rm -f ../../bin/x2c
	ln -s x2c-bootstrap ../../bin/x2c

clean:
	rm -f x2c *.[od]

realclean:
	rm -f x2c *.[odch]
	find . -mindepth 2 -name '*.h' -delete

.PHONY: clean realclean

###############################################################################
