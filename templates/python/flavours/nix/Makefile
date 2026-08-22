SHELL := /bin/bash

PROJECT_NAME := $(shell sed -n '/^[[:space:]]*[^#\[[:space:]]/p' PROJECT | head -1 | tr -d '[:space:]')
PROJECT_MODULE := $(shell echo $(PROJECT_NAME) | tr '-' '_')
PROJECT_VERSION := $(shell sed -n '/^[[:space:]]*[^#\[[:space:]]/p' PROJECT | sed -n '2p' | tr -d '[:space:]')
ifeq ($(PROJECT_NAME),)
    $(error Error: PROJECT file not found or invalid)
endif

PYTHON := python
RUFF := ruff
ARGS ?=
PYTHONPATH := $(CURDIR)/src
export PYTHONPATH

HAS_REL := $(shell command -v git-rel 2>/dev/null)

$(info ------------------------------------------)
$(info Project: $(PROJECT_NAME) v$(PROJECT_VERSION))
$(info Environment: pure Nix (no virtualenv))
$(info ------------------------------------------)

.PHONY: setup build b compile c run r test t check lint fmt fmt-check tidy clean verify release help h

setup:
	@$(PYTHON) -c 'import pytest' >/dev/null
	@$(RUFF) --version >/dev/null
	@echo "Nix Python environment is ready; no virtual environment is used."

build:
	@rm -rf dist
	@$(PYTHON) -m build --no-isolation --outdir dist

b: build

compile: clean build

c: compile

run:
	@$(PYTHON) -m $(PROJECT_MODULE) $(ARGS)

r: run

test:
	@$(PYTHON) -m pytest

t: test

check:
	@$(PYTHON) -m compileall -q src tests

lint:
	@$(RUFF) check .

fmt:
	@$(RUFF) format .
	@$(RUFF) check --fix .

fmt-check:
	@$(RUFF) format --check .

tidy: check

clean:
	@rm -rf dist build .pytest_cache .ruff_cache
	@find . -type d -name __pycache__ -prune -exec rm -rf {} +
	@find . -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete

verify: setup fmt-check lint check test

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
	@echo "Available targets: setup build compile run test check lint fmt fmt-check tidy clean verify release"
	@echo

h: help
