SHELL := /bin/bash

PROJECT_NAME := $(shell if [ -f PROJECT ]; then sed -n '/^[[:space:]]*[^#\[[:space:]]/p' PROJECT | head -1 | tr -d '[:space:]'; else basename "$$PWD"; fi)
PROJECT_VERSION := $(shell if [ -f PROJECT ]; then sed -n '/^[[:space:]]*[^#\[[:space:]]/p' PROJECT | sed -n '2p' | tr -d '[:space:]'; else sed -n 's/^[[:space:]]*\\.version[[:space:]]*=[[:space:]]*"\\([^"]*\\)".*/\\1/p' build.zig.zon | head -1; fi)
ifeq ($(PROJECT_NAME),)
    $(error Error: could not determine project name from PROJECT)
endif

PREFIX ?= $(HOME)/.local
ARGS ?=
OPTIMIZE ?= ReleaseFast

HAS_REL := $(shell command -v git-rel 2>/dev/null)

$(info ------------------------------------------)
$(info Project: $(PROJECT_NAME) v$(PROJECT_VERSION))
$(info ------------------------------------------)

.PHONY: build b compile c run r install uninstall test t check vet fmt fmt-check tidy clean verify release help h

build:
	@zig build -Doptimize=$(OPTIMIZE)

b: build

compile: clean build

c: compile

run:
	@zig build run -- $(ARGS)

r: run

install: build
	@install -d $(PREFIX)/bin
	@install -m 0755 zig-out/bin/$(PROJECT_NAME) $(PREFIX)/bin/$(PROJECT_NAME)
	@echo "installed -> $(PREFIX)/bin/$(PROJECT_NAME)"

uninstall:
	@rm -f $(PREFIX)/bin/$(PROJECT_NAME)
	@echo "removed -> $(PREFIX)/bin/$(PROJECT_NAME)"

test:
	@zig build test -Doptimize=$(OPTIMIZE)

t: test

check:
	@zig build test

vet: check

fmt:
	@zig fmt build.zig src

fmt-check:
	@zig fmt --check build.zig src

tidy:
	@zig build --fetch

clean:
	@rm -rf zig-out .zig-cache $(PROJECT_NAME)

verify: fmt-check test

release:
	@if [ -z "$(HAS_REL)" ]; then \
		echo "git-rel is not installed. Please install it first."; \
		exit 1; \
	fi
	@if [ -z "$(TYPE)" ]; then \
		echo "Release type not specified. Use 'make release TYPE=[patch|minor|major|M.m.p]'"; \
		exit 1; \
	fi
	@git rel $(TYPE)

help:
	@echo
	@echo "Usage: make [target]"
	@echo
	@echo "Available targets: build run install uninstall test check fmt fmt-check tidy clean verify release"
	@echo

h: help

