# AUTOMA GP — thin wrappers around scripts/ for everyday development.
# Run `make` or `make help` to list targets.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

SBCL       ?= sbcl
QL_SETUP   ?= $(HOME)/quicklisp/setup.lisp
WORKBENCH  := macos/AutomaGPWorkbench
SWIFT_CONF ?= release
AUTOMA_GP_WEB_PORT ?= 47391

.PHONY: help test web load lint workbench clean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "AUTOMA GP\n\nUsage: make <target>\n\nTargets:\n"} \
	      /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

test: ## Run the FiveAM suite (scripts/run-tests.sh)
	./scripts/run-tests.sh

web: ## Start the Hunchentoot console on http://127.0.0.1:$(AUTOMA_GP_WEB_PORT)/
	AUTOMA_GP_WEB_PORT=$(AUTOMA_GP_WEB_PORT) ./scripts/run-web.sh

load: ## Quickload automa-gp, automa-gp/web and automa-gp/tests; fail on any error
	@test -f "$(QL_SETUP)" || { echo "Quicklisp not found at $(QL_SETUP)" >&2; exit 1; }
	@mkdir -p "$(HOME)/quicklisp/local-projects"
	@ln -sfn "$(CURDIR)" "$(HOME)/quicklisp/local-projects/automa-gp"
	$(SBCL) --non-interactive --load "$(QL_SETUP)" \
	  --eval '(handler-bind ((warning (function muffle-warning))) (ql:quickload (list :automa-gp :automa-gp/web :automa-gp/tests) :silent t))' \
	  --eval '(format t "~&automa-gp ~A loaded~%" (symbol-value (find-symbol "*VERSION*" :automa-gp)))'

lint: ## markdownlint, yamllint, actionlint, shellcheck — each skipped when not installed
	@if command -v markdownlint-cli2 >/dev/null 2>&1; then \
	  echo ">> markdownlint-cli2"; markdownlint-cli2 "**/*.md"; \
	else echo ">> markdownlint-cli2 not installed, skipping (brew install markdownlint-cli2)"; fi
	@if command -v yamllint >/dev/null 2>&1; then \
	  echo ">> yamllint"; yamllint -c .yamllint.yaml .github .devcontainer .pre-commit-config.yaml CITATION.cff; \
	else echo ">> yamllint not installed, skipping (brew install yamllint)"; fi
	@if command -v actionlint >/dev/null 2>&1; then \
	  echo ">> actionlint"; actionlint; \
	else echo ">> actionlint not installed, skipping (brew install actionlint)"; fi
	@if command -v shellcheck >/dev/null 2>&1; then \
	  echo ">> shellcheck"; shellcheck -S warning scripts/*.sh; \
	else echo ">> shellcheck not installed, skipping (brew install shellcheck)"; fi

workbench: ## Build the macOS Workbench (swift build -c $(SWIFT_CONF))
	cd $(WORKBENCH) && swift build -c $(SWIFT_CONF)

clean: ## Remove compiled Lisp output for this tree and the Swift .build directory
	rm -rf "$(HOME)/.cache/common-lisp"/*/"$(CURDIR)"
	rm -rf $(WORKBENCH)/.build
	find . -name '*.fasl' -type f -delete
