###############################################################################

CFLAGS   += $(FLAGS)
SRCS		 =  $(wildcard *.c)
OBJS     =  $(SRCS:%.c=%.o)

.DELETE_ON_ERROR:

libx2c.a: $(OBJS)
	$(RM) $@
	$(AR) -cr $@ $(OBJS)

clean:
	rm -f libx2c.a *.[od]

realclean:
	rm -f libx2c.a *.[odch]

.PHONY: clean realclean

###############################################################################
