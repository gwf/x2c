###############################################################################

recursive_files = $(wildcard $1$2) $(foreach entry,$(wildcard $1*),$(call recursive_files,$(entry)/,$2))
CFLAGS   += $(FLAGS) $(foreach directory,$(sort $(dir $(SRCS))),-iquote $(directory))
SRCS     =  $(sort $(call recursive_files,./,*.c))
OBJS     =  $(SRCS:%.c=%.o)

.DELETE_ON_ERROR:

%.o: %.c
	@if test -f "$(@:.o=.xnm)"; then \
	  python3 ../native-layout-project.py --compile "$<" \
	    "../../builds/native/bootstrap/lib/$*.c" "$@" "$(@:.o=.d)" \
	    -- $(CC) $(CFLAGS); \
	else $(CC) $(CFLAGS) -c "$<" -o "$@"; fi

libx2c.a: $(OBJS)
	$(RM) $@
	$(AR) -cr $@ $(OBJS)

clean:
	rm -f libx2c.a $(call recursive_files,./,*.o) $(call recursive_files,./,*.d)

realclean:
	rm -f libx2c.a $(call recursive_files,./,*.o) $(call recursive_files,./,*.d) $(call recursive_files,./,*.c) $(call recursive_files,./,*.h) $(call recursive_files,./,*.xnm)

.PHONY: clean realclean

###############################################################################
