# Makefile to create soft links to all lib/*.h files in this directory

.PHONY: all clean

ROOT = ..
LIB_SOURCE = $(ROOT)/lib
LIB_BUILD = $(ROOT)/builds/0/lib

LIB_X_SRCS = $(notdir $(wildcard $(LIB_SOURCE)/*.x))
LIB_H_HDRS = $(patsubst %.x,%.h, $(LIB_X_SRCS))

all: $(LIB_X_SRCS) $(LIB_H_HDRS)

$(LIB_X_SRCS):
	@ln -sf $(LIB_SOURCE)/$@

$(LIB_H_HDRS):
	@ln -sf $(LIB_BUILD)/$@

clean:
	rm -f $(LIB_X_SRCS) $(LIB_H_HDRS)
	find . -type l -delete
