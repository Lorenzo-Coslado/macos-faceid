SDK   := $(shell xcrun --show-sdk-path)
CC    := clang
MACOSX_DEPLOYMENT_TARGET ?= 14.0
TARGET  := arm64-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)
CFLAGS  := -Wall -Wextra -O2 -isysroot $(SDK) -target $(TARGET)
LDFLAGS := -bundle -lpam

pam_faceid.so: pam_faceid.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm -f pam_faceid.so

.PHONY: clean
