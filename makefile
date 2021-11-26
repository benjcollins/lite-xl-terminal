CFLAGS=-O2

ifeq ($(OS),Windows_NT)
	SRC=win/terminal.c
else
	SRC=terminal.c
	CFLAGS+=-lutil
endif

terminal: ${SRC}
	$(CC) -o $@ $< $(CFLAGS)
