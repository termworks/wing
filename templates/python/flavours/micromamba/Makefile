SHELL := /bin/bash

PROJECT_NAME := $(shell sed -n '/^[[:space:]]*[^#\[[:space:]]/p' PROJECT | head -1 | tr -d '[:space:]')
PROJECT_MODULE := $(shell echo $(PROJECT_NAME) | tr '-' '_')
PROJECT_VERSION := $(shell sed -n '/^[[:space:]]*[^#\[[:space:]]/p' PROJECT | sed -n '2p' | tr -d '[:space:]')
ifeq ($(PROJECT_NAME),)
    $(error Error: PROJECT file not found or invalid)
endif

MICROMAMBA := micromamba
MAMBA_ROOT_PREFIX ?= $(CURDIR)/.micromamba
ENV_PREFIX ?= $(MAMBA_ROOT_PREFIX)/envs/$(PROJECT_NAME)
RUN := $(MICROMAMBA) run --prefix $(ENV_PREFIX)
ARGS ?=
export MAMBA_ROOT_PREFIX

HAS_REL := $(shell command -v git-rel 2>/dev/null)

$(info ------------------------------------------)
$(info Project: $(PROJECT_NAME) v$(PROJECT_VERSION))
$(info Environment: micromamba ($(ENV_PREFIX)))
$(info ------------------------------------------)

.PHONY: setup build b compile c run r test t check lint fmt fmt-check tidy clean verify release help h

setup:
	@if [ -x "$(ENV_PREFIX)/bin/python" ]; then \
		$(MICROMAMBA) env update --yes --prefix "$(ENV_PREFIX)" --file environment.yml; \
	else \
		$(MICROMAMBA) create --yes --prefix "$(ENV_PREFIX)" --file environment.yml; \
	fi

build: setup
	@rm -rf dist
	@PYTHONPATH=src $(RUN) python -m build --no-isolation --outdir dist

b: build

compile: clean build

c: compile

run: setup
	@PYTHONPATH=src $(RUN) python -m $(PROJECT_MODULE) $(ARGS)

r: run

test: setup
	@PYTHONPATH=src $(RUN) pytest

t: test

check: setup
	@PYTHONPATH=src $(RUN) python -m compileall -q src tests

lint: setup
	@$(RUN) ruff check .

fmt: setup
	@$(RUN) ruff format .
	@$(RUN) ruff check --fix .

fmt-check: setup
	@$(RUN) ruff format --check .

tidy: setup

clean:
	@rm -rf .micromamba dist build .pytest_cache .ruff_cache
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
