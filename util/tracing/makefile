# Makefile for utilities that convert Lingua Franca trace files
# into other formats.
# @author: Edward A. Lee

CC=gcc
CFLAGS=-I../../xtext/org.icyphy.linguafranca/src/lib/core/ -Wall
DEPS=

%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

trace_to_csv: trace_to_csv.o trace_util.o
	$(CC) -o trace_to_csv trace_to_csv.o trace_util.o
	
trace_to_chrome: trace_to_chrome.o trace_util.o
	$(CC) -o trace_to_chrome trace_to_chrome.o trace_util.o

install: trace_to_csv trace_to_chrome
	mv trace_to_csv ../../bin
	mv trace_to_chrome ../../bin
	
clean:
	rm -f *.o

 
