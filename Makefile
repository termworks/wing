SHELL := /bin/bash

PROJECT_NAME := wing
NIMBLE_FILE := wing.nimble
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
BOBABREW_SRC := $(shell if [ -n "$$NIMBLE_DIR" ] && [ -d "$$NIMBLE_DIR/pkgcache/githubcom_bresillabobabrew/src" ]; then printf '%s' "$$NIMBLE_DIR/pkgcache/githubcom_bresillabobabrew/src"; elif [ -n "$$NIMBLE_DIR" ] && [ -d "$$NIMBLE_DIR/pkgcache/githubcom_bresillabobabrew_0.1.0/src" ]; then printf '%s' "$$NIMBLE_DIR/pkgcache/githubcom_bresillabobabrew_0.1.0/src"; elif [ -d "$(TOP_DIR)/../bobabrew/src" ]; then printf '%s' "$(TOP_DIR)/../bobabrew/src"; fi)
NIM_FLAGS ?=
ifneq ($(BOBABREW_SRC),)
    NIM_FLAGS += --path:$(BOBABREW_SRC)
endif

HAS_REL := $(shell command -v git-rel 2>/dev/null)
HAS_CLIFF := $(shell command -v git-cliff 2>/dev/null)

$(info ------------------------------------------)
$(info Project: $(PROJECT_NAME) v$(PROJECT_VERSION))
$(info ------------------------------------------)

.PHONY: build b compile c run r install uninstall test t test-all cover check vet fmt fmt-check tidy clean changelog verify release mdbook help h

build:
	@$(NIM) c $(NIM_FLAGS) $(BUILD_FLAGS) --out:$(PROJECT_NAME) src/wing.nim

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
	@$(NIM) c $(NIM_FLAGS) -d:release --out:/tmp/wing-release-check src/wing.nim
	@rm -f /tmp/wing-release-check

cover:
	@echo "coverage is not configured for this Nim project yet; running tests instead"
	@$(MAKE) test

check:
	@$(NIM) check $(NIM_FLAGS) src/wing.nim

vet: check

fmt:
	@$(NIMPRETTY) $(NIM_FILES)

fmt-check:
	@set -e; \
	needed=""; \
	for f in $(NIM_FILES); do \
		tmp="/tmp/wing-nimpretty-$$(basename "$$f").$$$$.nim"; \
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

mdbook:
	@mdbook build book --dest-dir ../docs
	@git add -A && git commit -m "docs: building website/mdbook"

help:
	@echo
	@echo "Usage: make [target]"
	@echo
	@echo "Available targets:"
	@echo "  build        Build the binary (./$(PROJECT_NAME))"
	@echo "  compile      Clean and rebuild"
	@echo "  run          Run locally (pass args with ARGS=...)"
	@echo "  install      Install to \$$PREFIX/bin (default ~/.local/bin)"
	@echo "  uninstall    Remove the installed binary"
	@echo "  test         Run all tests"
	@echo "  test-all     Run tests plus release compile check"
	@echo "  cover        Run tests (coverage not configured yet)"
	@echo "  check        Run Nim semantic checks"
	@echo "  vet          Alias for check"
	@echo "  fmt          Format Nim sources"
	@echo "  fmt-check    Fail if Nim sources are unformatted"
	@echo "  tidy         Install Nim dependencies"
	@echo "  clean        Remove build artifacts"
	@echo "  changelog    Regenerate CHANGELOG.md (git-cliff)"
	@echo "  verify       Run the full local gate (fmt-check + check + test)"
	@echo "  release      Release a new version (git-rel)"
	@echo "  mdbook       Build the mdbook into ../docs"
	@echo
	@echo "Examples:"
	@echo "  make run ARGS='project list'"
	@echo "  make install PREFIX=/usr/local"
	@echo "  make release TYPE=minor"
	@echo

h: help
