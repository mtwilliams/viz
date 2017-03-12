ERL_INCLUDE_PATH ?= $(shell erl -eval 'io:format("~s~n", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])])' -s init stop -noshell)

CC ?= clang
CFLAGS = -g -O3 -std=c99 -pedantic -Wall -Wextra -Wno-zero-length-array
CFLAGS += -I$(ERL_INCLUDE_PATH)
LDFLAGS =

ifneq ($(OS),Windows_NT)
  CFLAGS += -fPIC
  ifeq ($(shell uname),Darwin)
    LDFLAGS += -dynamiclib -undefined dynamic_lookup
  endif
endif

.PHONY: all nif clean

all: nif

nif: priv/bitset.so

priv/bitset.so: c_src/bitset.c
	$(CC) $(CFLAGS) -shared $(LDFLAGS) -o $@ c_src/bitset.c

clean:
	$(RM) priv/bitset.so
	$(RM) -R priv/bitset.so.dSYM
