SHELL := /bin/bash

PROJECT_NAME := $(shell sed -n '/^[[:space:]]*[^#\[[:space:]]/p' PROJECT | head -1 | tr -d '[:space:]')
PROJECT_VERSION := $(shell sed -n '/^[[:space:]]*[^#\[[:space:]]/p' PROJECT | sed -n '2p' | tr -d '[:space:]')
ifeq ($(PROJECT_NAME),)
    $(error Error: PROJECT file not found or invalid)
endif

PROJECT_TARGET := $(shell echo $(PROJECT_NAME) | tr '-' '_')
PROJECT_CAP := $(shell echo $(PROJECT_TARGET) | tr '[:lower:]' '[:upper:]')
TOP_DIR := $(CURDIR)
BUILD_DIR := $(TOP_DIR)/build
PREFIX ?= $(HOME)/.local
CC ?=

HAS_REL := $(shell command -v git-rel 2>/dev/null)

ifdef CC
    ifeq ($(CC),gcc)
        CMAKE_COMPILER_FLAG := -DCOMPILER=gcc
    else ifeq ($(CC),clang)
        CMAKE_COMPILER_FLAG := -DCOMPILER=clang
    endif
endif

$(info ------------------------------------------)
$(info Project: $(PROJECT_NAME) v$(PROJECT_VERSION))
$(info Compiler: $(CC))
$(info ------------------------------------------)

.PHONY: build b config c reconfig compile run r test t fmt fmt-check clean verify release help h

config:
	@mkdir -p $(BUILD_DIR)
	@cd $(BUILD_DIR) && cmake -Wno-dev $(CMAKE_COMPILER_FLAG) -D$(PROJECT_TARGET)_ENABLE_TESTS=ON -D$(PROJECT_TARGET)_BUILD_EXAMPLES=ON ..

c: config

build:
	@$(MAKE) fmt
	@if [ ! -d "$(BUILD_DIR)" ]; then $(MAKE) config; fi
	@cd $(BUILD_DIR) && $(MAKE) -j$$(nproc)

b: build

compile: clean build

run:
	@echo "No runnable example is configured yet."

r: run

test:
	@if [ ! -d "$(BUILD_DIR)" ]; then $(MAKE) config; fi
	@cd $(BUILD_DIR) && ctest --verbose --output-on-failure

t: test

fmt:
	@find ./src ./include ./test \( -name "*.cpp" -o -name "*.hpp" -o -name "*.h" \) | xargs clang-format -i

fmt-check:
	@find ./src ./include ./test \( -name "*.cpp" -o -name "*.hpp" -o -name "*.h" \) | xargs clang-format --dry-run --Werror

clean:
	@rm -rf $(BUILD_DIR)

verify: fmt-check build test

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
	@echo "Available targets: config build compile test fmt fmt-check clean verify release"
	@echo

h: help
