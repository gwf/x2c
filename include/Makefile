# Development headers and sources mirror the runtime module layout.
.PHONY: all clean

ROOT = ..
LIB_SOURCE = $(ROOT)/lib
LIB_BUILD = $(ROOT)/builds/0/lib
HEADER_DIR = x2c
LIB_ENTRIES = $(shell python3 $(ROOT)/tools/sources.py --root $(ROOT) --area lib)

all:
	@mkdir -p $(HEADER_DIR)
	@find $(HEADER_DIR) -type l -delete
	@for source in $(LIB_SOURCE)/*.x $(LIB_SOURCE)/*/*.x; do \
	  relative=$${source#$(LIB_SOURCE)/}; \
	  directory=$${relative%/*}; prefix=../; \
	  if [ "$$directory" != "$$relative" ]; then \
	    mkdir -p "$(HEADER_DIR)/$$directory"; prefix=../../; \
	  fi; \
	  ln -sf "$$prefix$$source" "$(HEADER_DIR)/$$relative"; \
	done
	@for source in $(LIB_ENTRIES); do \
	  relative=$${source#$(LIB_SOURCE)/}; \
	  name=$${relative##*/}; name=$${name%.x}.h; \
	  ln -sf "../$(LIB_BUILD)/$$name" "$(HEADER_DIR)/$$name"; \
	  directory=$${relative%/*}; \
	  if [ "$$directory" != "$$relative" ]; then \
	    ln -sf "../../$(LIB_BUILD)/$$directory/$$name" "$(HEADER_DIR)/$$directory/$$name"; \
	  fi; \
	done

clean:
	rm -rf $(HEADER_DIR)
	find . -type l -delete
