CFLAGS?=

ifeq ($(OS),Windows_NT)
	SRC=terminal.win.c
	CFLAGS+=-lwinpty
else
	SRC=terminal.c
	CFLAGS+=-lutil
endif

debug: CFLAGS+=-O0 -g
debug: terminal

release: CFLAGS+=-O2
release: terminal

terminal: ${SRC}
	$(CC) -o $@ $< $(CFLAGS)

.PHONY: debug release
