###############################################################################

CFLAGS   =	-iquote ../lib $(FLAGS)
LDFLAGS  =	-L../lib -lx2c -lm
SRCS     =  $(wildcard *.c)
OBJS     =  $(SRCS:%.c=%.o)
# A native module binds to the compiler's own runtime, so the compiler links
# the whole runtime archive, and a Linux executable exports its functions
# only when asked.
UNAME_S  := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
LDFLAGS  =	-Wl,-force_load,../lib/libx2c.a -lm
endif
ifeq ($(UNAME_S),Linux)
LDFLAGS  =	-L../lib -Wl,--whole-archive -lx2c -Wl,--no-whole-archive -lm
LDFLAGS  +=	-rdynamic
endif

.DELETE_ON_ERROR:

../../bin/x2c: x2c install

x2c: $(OBJS) ../lib/libx2c.a
	$(CC) -o $@ $(OBJS) $(LDFLAGS)
	rm -f ../../bin/x2c-bootstrap
	cp x2c ../../bin/x2c-bootstrap

install:
	rm -f ../../bin/x2c
	ln -s x2c-bootstrap ../../bin/x2c

clean:
	rm -f x2c *.[od]

realclean:
	rm -f x2c *.[odch]

.PHONY: clean realclean

###############################################################################
