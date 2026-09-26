# Makefile to create soft links to all lib/*.h files under x2c/ in this
# directory, so a consumer compiles with -I <prefix>/include and writes
# #include <x2c/string.h> without shadowing a system header.

.PHONY: all clean

ROOT = ..
LIB_SOURCE = $(ROOT)/lib
LIB_BUILD = $(ROOT)/builds/0/lib
HEADER_DIR = x2c

LIB_X_SRCS = $(addprefix $(HEADER_DIR)/,\
  $(notdir $(wildcard $(LIB_SOURCE)/*.x)))
LIB_H_HDRS = $(patsubst %.x,%.h, $(LIB_X_SRCS))

# A link whose lib/ source was deleted is removed.
all: $(LIB_X_SRCS) $(LIB_H_HDRS)
	@for link in $(HEADER_DIR)/*; do \
	  case " $(LIB_X_SRCS) $(LIB_H_HDRS) " in \
	    *" $$link "*) ;; \
	    *) [ ! -L "$$link" ] || rm -f "$$link" ;; \
	  esac; \
	done

$(LIB_X_SRCS): | $(HEADER_DIR)
	@ln -sf ../$(LIB_SOURCE)/$(@F) $@

$(LIB_H_HDRS): | $(HEADER_DIR)
	@ln -sf ../$(LIB_BUILD)/$(@F) $@

$(HEADER_DIR):
	@mkdir -p $@

clean:
	rm -rf $(HEADER_DIR)
	find . -type l -delete
