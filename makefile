CC=gcc
CFLAGS=-lutil

terminal: terminal.c
	$(CC) -o terminal terminal.c $(CFLAGS)