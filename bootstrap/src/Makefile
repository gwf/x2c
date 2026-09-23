###############################################################################

CFLAGS   =	-iquote ../lib $(FLAGS)
LDFLAGS  =	-L../lib -lx2c -lm
SRCS     =  $(wildcard *.c)
OBJS     =  $(SRCS:%.c=%.o)
# A native module binds to the compiler's own runtime. The compiler links
# whole every runtime object etc/runtime-objects.sh selects, and a Linux
# executable exports its functions only when asked.
UNAME_S  := $(shell uname -s)
SELECT   =	:
ifneq ($(filter Darwin Linux,$(UNAME_S)),)
SELECT   =	sh ../../etc/runtime-objects.sh
endif
ifeq ($(UNAME_S),Linux)
LDFLAGS  +=	-rdynamic
endif

.DELETE_ON_ERROR:

../../bin/x2c: x2c install

x2c: $(OBJS) ../lib/libx2c.a
	whole=$$($(SELECT) $(OBJS) -- ../lib/*.o) && \
	$(CC) -o $@ $(OBJS) $$whole $(LDFLAGS)
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
