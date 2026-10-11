###############################################################################

recursive_files = $(wildcard $1$2) $(foreach entry,$(wildcard $1*),$(call recursive_files,$(entry)/,$2))
LIB_SRCS =  $(sort $(call recursive_files,../lib/,*.c))
CFLAGS   =	-iquote ../lib $(foreach directory,$(sort $(dir $(LIB_SRCS) $(SRCS))),-iquote $(directory)) $(FLAGS)
LDFLAGS  =	-L../lib -lx2c -lm
SRCS     =  $(sort $(call recursive_files,./,*.c))
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

%.o: %.c
	@if test -f "$(@:.o=.xnm)"; then \
	  python3 ../native-layout-project.py --compile "$<" \
	    "../../builds/native/bootstrap/src/$*.c" "$@" "$(@:.o=.d)" \
	    -- $(CC) $(CFLAGS); \
	else $(CC) $(CFLAGS) -c "$<" -o "$@"; fi

x2c: $(OBJS) ../lib/libx2c.a
	$(CC) -o $@ $(OBJS) $(LDFLAGS)
	rm -f ../../bin/x2c-bootstrap
	cp x2c ../../bin/x2c-bootstrap

install:
	rm -f ../../bin/x2c
	ln -s x2c-bootstrap ../../bin/x2c

clean:
	rm -f x2c $(call recursive_files,./,*.o) $(call recursive_files,./,*.d)

realclean:
	rm -f x2c $(call recursive_files,./,*.o) $(call recursive_files,./,*.d) $(call recursive_files,./,*.c) $(call recursive_files,./,*.h)

.PHONY: clean realclean

###############################################################################
