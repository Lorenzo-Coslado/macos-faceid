SDK   := $(shell xcrun --show-sdk-path)
CC    := clang
CFLAGS  := -Wall -Wextra -O2 -isysroot $(SDK)
LDFLAGS := -bundle -lpam

pam_faceid.so: pam_faceid.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm -f pam_faceid.so

.PHONY: clean
