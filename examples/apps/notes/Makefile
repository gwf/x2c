ROOT := ../../..
SOURCES := notes.x service.x store.x record.x

.PHONY: all build run check clean
all: build
build: builds/notes

builds/notes: $(SOURCES)
	mkdir -p builds
	cd $(ROOT) && ./builds/0/x2c build -o examples/apps/notes/$@ \
	  $(addprefix examples/apps/notes/,$(SOURCES))

run: builds/notes
	cd $(ROOT) && examples/apps/notes/builds/notes

check: builds/notes
	cd $(ROOT) && examples/apps/notes/builds/notes --check

clean:
	rm -rf builds
