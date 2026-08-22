SHELL := /bin/bash

PROJECT_NAME := {{kebab_name}}
NIMBLE_FILE := {{snake_name}}.nimble
PROJECT_VERSION := $(shell sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' $(NIMBLE_FILE) | head -1)
ifeq ($(PROJECT_VERSION),)
    $(error Error: could not determine project version from $(NIMBLE_FILE))
endif

TOP_DIR := $(CURDIR)
NIM := nim
NIMBLE := nimble
NIMPRETTY := nimpretty
PREFIX ?= $(HOME)/.local
ARGS ?=
BUILD_FLAGS ?= -d:release
NIM_FILES := $(shell find src tests -name '*.nim' -type f | sort)

HAS_REL := $(shell command -v git-rel 2>/dev/null)
HAS_CLIFF := $(shell command -v git-cliff 2>/dev/null)

$(info ------------------------------------------)
$(info Project: $(PROJECT_NAME) v$(PROJECT_VERSION))
$(info ------------------------------------------)

.PHONY: build b compile c run r install uninstall test t test-all cover check vet fmt fmt-check tidy clean changelog verify release help h

build:
	@$(NIM) c $(BUILD_FLAGS) --out:$(PROJECT_NAME) src/{{snake_name}}.nim

b: build

compile:
	@$(MAKE) clean
	@$(MAKE) build

c: compile

run: build
	@./$(PROJECT_NAME) $(ARGS)

r: run

install: build
	@install -d $(PREFIX)/bin
	@install -m 0755 $(PROJECT_NAME) $(PREFIX)/bin/$(PROJECT_NAME)
	@echo "installed -> $(PREFIX)/bin/$(PROJECT_NAME)"

uninstall:
	@rm -f $(PREFIX)/bin/$(PROJECT_NAME)
	@echo "removed -> $(PREFIX)/bin/$(PROJECT_NAME)"

test:
	@$(NIMBLE) test -y

t: test

test-all:
	@$(NIMBLE) test -y
	@$(NIM) c -d:release --out:/tmp/{{kebab_name}}-release-check src/{{snake_name}}.nim
	@rm -f /tmp/{{kebab_name}}-release-check

cover:
	@echo "coverage is not configured for this Nim project yet; running tests instead"
	@$(MAKE) test

check:
	@$(NIM) check src/{{snake_name}}.nim

vet: check

fmt:
	@$(NIMPRETTY) $(NIM_FILES)

fmt-check:
	@set -e; \
	needed=""; \
	for f in $(NIM_FILES); do \
		tmp="/tmp/{{kebab_name}}-nimpretty-$$(basename "$$f").$$$$.nim"; \
		cp "$$f" "$$tmp"; \
		$(NIMPRETTY) "$$tmp" >/dev/null; \
		if ! cmp -s "$$f" "$$tmp"; then needed="$$needed $$f"; fi; \
		rm -f "$$tmp"; \
	done; \
	if [ -n "$$needed" ]; then echo "nimpretty needed on:$$needed"; exit 1; fi

tidy:
	@$(NIMBLE) install -y --depsOnly

clean:
	@rm -f $(PROJECT_NAME) coverage.out
	@rm -rf bin nimcache
	@find tests -maxdepth 1 -type f -name 'test_*' ! -name '*.nim' -delete

changelog:
	@if [ -z "$(HAS_CLIFF)" ]; then \
		echo "git-cliff is not installed. Please install it first."; \
		exit 1; \
	fi
	@git cliff -o CHANGELOG.md

verify: fmt-check check test

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

