# sourced by https://github.com/octomation/makefiles

.DEFAULT_GOAL = test-with-coverage

SHELL = /bin/bash -euo pipefail

GO111MODULE = on
GOFLAGS     = -mod=vendor
GOPRIVATE   = go.octolab.net
GOPROXY     = direct
LOCAL       = $(MODULE)
MODULE      = `go list -m`
PACKAGES    = `go list ./... 2> /dev/null`
PATHS       = $(shell echo $(PACKAGES) | sed -e "s|$(MODULE)/\{0,1\}||g")
TIMEOUT     = 1s

ifeq (, $(PACKAGES))
	PACKAGES = $(MODULE)
endif

ifeq (, $(PATHS))
	PATHS = .
endif

export GO111MODULE := $(GO111MODULE)
export GOFLAGS     := $(GOFLAGS)
export GOPRIVATE   := $(GOPRIVATE)
export GOPROXY     := $(GOPROXY)

.PHONY: go-env
go-env:
	@echo "GO111MODULE: `go env GO111MODULE`"
	@echo "GOFLAGS:     $(strip `go env GOFLAGS`)"
	@echo "GOPRIVATE:   $(strip `go env GOPRIVATE`)"
	@echo "GOPROXY:     $(strip `go env GOPROXY`)"
	@echo "LOCAL:       $(LOCAL)"
	@echo "MODULE:      $(MODULE)"
	@echo "PACKAGES:    $(PACKAGES)"
	@echo "PATHS:       $(strip $(PATHS))"
	@echo "TIMEOUT:     $(TIMEOUT)"

.PHONY: deps-check
deps-check:
	@go mod verify
	@if command -v egg > /dev/null; then \
		egg deps check license; \
		egg deps check version; \
	fi

.PHONY: deps-clean
deps-clean:
	@go clean -modcache

.PHONY: deps-shake
deps-shake:
	@go mod tidy

.PHONY: module-deps
module-deps:
	@go mod download
	@if [[ "`go env GOFLAGS`" =~ -mod=vendor ]]; then go mod vendor; fi

.PHONY: update
update: selector = '{{if not (or .Main .Indirect)}}{{.Path}}{{end}}'
update:
	@if command -v egg > /dev/null; then \
		packages="`egg deps list`"; \
	else \
		packages="`go list -f $(selector) -m all`"; \
	fi; GOFLAGS=-mod= go get -d -u $$packages

.PHONY: update-all
update-all:
	@go get -d -mod= -u ./...

.PHONY: format
format:
	@goimports -local $(LOCAL) -ungroup -w $(PATHS)

.PHONY: go-generate
go-generate:
	@go generate $(PACKAGES)

.PHONY: lint
lint:
	@golangci-lint run ./...

.PHONY: test
test:
	@go test -race -timeout $(TIMEOUT) $(PACKAGES)

.PHONY: test-clean
test-clean:
	@go clean -testcache

.PHONY: test-with-coverage
test-with-coverage:
	@go test -cover -timeout $(TIMEOUT) $(PACKAGES) | column -t | sort -r

.PHONY: test-with-coverage-profile
test-with-coverage-profile:
	@go test -cover -covermode count -coverprofile c.out -timeout $(TIMEOUT) $(PACKAGES)

BINARY  = $(BINPATH)/$(shell basename $(MAIN))
BINPATH = $(PWD)/bin
COMMIT  = $(shell git rev-parse --verify HEAD)
DATE    = $(shell date +%Y-%m-%dT%T%Z)
LDFLAGS = -ldflags "-s -w -X main.commit=$(COMMIT) -X main.date=$(DATE)"
MAIN    = $(MODULE)

export GOBIN := $(BINPATH)
export PATH  := $(BINPATH):$(PATH)

.PHONY: build-env
build-env:
	@echo "BINARY:      $(BINARY)"
	@echo "BINPATH:     $(BINPATH)"
	@echo "COMMIT:      $(COMMIT)"
	@echo "DATE:        $(DATE)"
	@echo "GOBIN:       `go env GOBIN`"
	@echo "LDFLAGS:     $(LDFLAGS)"
	@echo "MAIN:        $(MAIN)"
	@echo "PATH:        $$PATH"

.PHONY: build
build:
	@go build -o $(BINARY) $(LDFLAGS) $(MAIN)

.PHONY: build-clean
build-clean:
	@rm -f $(BINARY)

.PHONY: install
install:
	@go install $(LDFLAGS) $(MAIN)

.PHONY: install-clean
install-clean:
	@go clean -cache

.PHONY: dist-check
dist-check:
	@goreleaser --snapshot --skip-publish --rm-dist

.PHONY: dist-dump
dist-dump:
	@godownloader .goreleaser.yml > bin/install

TOOLFLAGS = -mod=

.PHONY: tools-env
tools-env:
	@echo "GOBIN:       `go env GOBIN`"
	@echo "TOOLFLAGS:   $(TOOLFLAGS)"

.PHONY: toolset
toolset:
	@( \
		GOFLAGS=$(TOOLFLAGS); \
		cd tools; \
		go mod download; \
		if [[ "`go env GOFLAGS`" =~ -mod=vendor ]]; then go mod vendor; fi; \
		go generate tools.go; \
	)


.PHONY: clean
clean: build-clean deps-clean install-clean test-clean

.PHONY: deps
deps: module-deps toolset

.PHONY: env
env: go-env build-env tools-env

.PHONY: generate
generate: go-generate format

.PHONY: refresh
refresh: deps-shake update deps generate format test build
