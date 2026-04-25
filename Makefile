REDBEAN_VERSION := $(shell cat .redbean-version)
REDBEAN_URL      = https://redbean.dev/redbean-$(REDBEAN_VERSION).com

HURL_VERSION  := $(shell cat .hurl-version)
HURL_OS       := $(shell uname -s)
HURL_RAW_ARCH := $(shell uname -m)
HURL_ARCH     := $(if $(filter arm64,$(HURL_RAW_ARCH)),aarch64,$(HURL_RAW_ARCH))

ifneq (,$(or $(findstring MINGW,$(HURL_OS)),$(findstring MSYS,$(HURL_OS)),$(findstring CYGWIN,$(HURL_OS))))
HURL_PLATFORM  = x86_64-pc-windows-msvc
HURL_URL       = https://github.com/Orange-OpenSource/hurl/releases/download/$(HURL_VERSION)/hurl-$(HURL_VERSION)-$(HURL_PLATFORM).zip
else ifeq ($(HURL_OS),Darwin)
HURL_PLATFORM  = $(HURL_ARCH)-apple-darwin
HURL_URL       = https://github.com/Orange-OpenSource/hurl/releases/download/$(HURL_VERSION)/hurl-$(HURL_VERSION)-$(HURL_PLATFORM).tar.gz
else
HURL_PLATFORM  = $(HURL_ARCH)-unknown-linux-gnu
HURL_URL       = https://github.com/Orange-OpenSource/hurl/releases/download/$(HURL_VERSION)/hurl-$(HURL_VERSION)-$(HURL_PLATFORM).tar.gz
endif

STYLUA_VERSION  := $(shell cat .stylua-version)
STYLUA_OS       := $(shell uname -s)
STYLUA_RAW_ARCH := $(shell uname -m)
STYLUA_ARCH     := $(if $(filter arm64,$(STYLUA_RAW_ARCH)),aarch64,$(STYLUA_RAW_ARCH))

ifeq ($(STYLUA_OS),Darwin)
STYLUA_PLATFORM = macos-$(STYLUA_ARCH)
else
STYLUA_PLATFORM = linux-$(STYLUA_ARCH)
endif
STYLUA_URL = https://github.com/JohnnyMorganz/StyLua/releases/download/v$(STYLUA_VERSION)/stylua-$(STYLUA_PLATFORM).zip

LUACHECK_VERSION := $(shell cat .luacheck-version)
LUACHECK_URL = https://github.com/lunarmodules/luacheck/releases/download/v$(LUACHECK_VERSION)/luacheck

LUACOV_VERSION := $(shell cat .luacov-version)
LUACOV_URL = https://github.com/lunarmodules/luacov/archive/refs/tags/v$(LUACOV_VERSION).tar.gz

REDBEAN_BIN = redbean.com

$(REDBEAN_BIN): .redbean-version
	curl -fsSL $(REDBEAN_URL) -o $(REDBEAN_BIN)
	chmod +x $(REDBEAN_BIN)

# Reusable macro: run a Redbean script.
# Usage: $(call REDBEAN,scripts/foo.lua [args...])
# Declares REDBEAN_BIN as a dependency and invokes it with -i.
REDBEAN = ./$(REDBEAN_BIN) -i

# Shared dependency groups for script targets.
INIT_SRCS    = .init.lua $(wildcard internal/*.lua)
BACKEND_SRCS = $(INIT_SRCS) $(wildcard backends/*.lua)

hurl: .hurl-version
ifneq (,$(or $(findstring MINGW,$(HURL_OS)),$(findstring MSYS,$(HURL_OS)),$(findstring CYGWIN,$(HURL_OS))))
	curl -sL $(HURL_URL) -o hurl.zip
	unzip -p hurl.zip hurl-$(HURL_VERSION)-$(HURL_PLATFORM)/bin/hurl.exe > hurl
	chmod +x hurl
	rm hurl.zip
else
	curl -fsSL $(HURL_URL) | tar -xz --strip-components=2 hurl-$(HURL_VERSION)-$(HURL_PLATFORM)/bin/hurl
	chmod +x hurl
endif

stylua: .stylua-version
	curl -fsSL $(STYLUA_URL) -o /tmp/stylua-download.zip
	unzip -p /tmp/stylua-download.zip stylua > stylua
	rm /tmp/stylua-download.zip
	chmod +x stylua

luacheck: .luacheck-version
	curl -fsSL $(LUACHECK_URL) -o luacheck
	chmod +x luacheck

luacov: .luacov-version
	rm -rf luacov
	mkdir -p luacov
	curl -fsSL $(LUACOV_URL) | tar -xz --strip-components=2 -C luacov luacov-$(LUACOV_VERSION)/src

confusio.com: $(REDBEAN_BIN) .init.lua $(wildcard backends/*.lua) $(wildcard internal/*.lua)
	cp $(REDBEAN_BIN) confusio.com
	zip confusio.com .init.lua $(wildcard backends/*.lua) $(wildcard internal/*.lua)

mock-%.com: $(REDBEAN_BIN) test/mock-%.lua
	cp $(REDBEAN_BIN) $@
	@mkdir -p .tmp-mock-$*
	cp test/mock-$*.lua .tmp-mock-$*/.init.lua
	(cd .tmp-mock-$* && zip -u ../$@ .init.lua)
	rm -rf .tmp-mock-$*

# Family-alias mock rules: build mock-<alias>.com from the root family's mock lua
# instead of a per-alias test/mock-<alias>.lua.  Explicit rules take precedence over
# the mock-%.com pattern rule above.
# ALIAS_MOCK_RULE(alias, root): builds mock-<alias>.com from test/mock-<root>.lua
define ALIAS_MOCK_RULE
mock-$(1).com: $(REDBEAN_BIN) test/mock-$(2).lua
	cp $(REDBEAN_BIN) $$@
	@mkdir -p .tmp-mock-$(1)
	cp test/mock-$(2).lua .tmp-mock-$(1)/.init.lua
	(cd .tmp-mock-$(1) && zip -u ../$$@ .init.lua)
	rm -rf .tmp-mock-$(1)
endef

DUMP_ENDPOINTS_SCRIPT       = scripts/dump-endpoints.lua
DUMP_FAMILIES_SCRIPT        = scripts/dump-families.lua
DUMP_CLAIMS_SCRIPT          = scripts/dump-claims.lua
DUMP_CAPS_SCRIPT            = scripts/dump-capabilities.lua
VALIDATE_CLAIMS_SCRIPT      = scripts/validate-claims.lua
VALIDATE_CAPS_SCRIPT        = scripts/validate-capabilities.lua
GEN_GRAPHQL_SCHEMA_SCRIPT   = scripts/gen-graphql-schema.lua

# .make-families.mk is auto-generated from provider_families in .init.lua.
# It contains $(eval $(call ALIAS_MOCK_RULE,...)) lines for every family alias
# so that mock-<alias>.com is built from the root family's mock lua.
# If the file does not exist, Make rebuilds it before re-reading the Makefile.
-include .make-families.mk

.make-families.mk: $(REDBEAN_BIN) $(DUMP_FAMILIES_SCRIPT) $(INIT_SRCS)
	$(REDBEAN) $(DUMP_FAMILIES_SCRIPT) | python3 scripts/gen-family-mk.py > $@

# Backend test configuration.
# To add a standalone backend: append to BACKENDS (ports auto-assigned from 18080).
# Each backend needs test/mock-<name>.lua and at least one test/<name>-*.hurl file
# (symlinks ok — used by wildcard discovery).
# To add a family-alias backend: add to BACKENDS; no test/mock-<name>.lua needed —
# .make-families.mk auto-generates mock-<alias>.com from the root family's mock.
BACKENDS = azuredevops bitbucket bitbucket_datacenter codeberg codecommit forgejo gerrit gitblit gitbucket gitea gitlab gogs \
           harness kallithea launchpad notabug onedev pagure phabricator radicle \
           rhodecode sourceforge sourcehut tuleap
MOCKS    = $(addprefix mock-,$(addsuffix .com,$(BACKENDS)))

$(eval _p := 18080)
$(foreach b,$(BACKENDS),$(eval $(b)_CPORT := $(_p))$(eval $(b)_MPORT := $(shell expr $(_p) + 1))$(eval _p := $(shell expr $(_p) + 2)))

define BACKEND_RULE
.PHONY: test-unit-$(1)
test-unit-$(1): confusio.com mock-$(1).com hurl
	bash test/run-backend.sh mock-$(1).com \
	  $($(1)_CPORT) $($(1)_MPORT) \
	  "-- $(1) http://127.0.0.1:$($(1)_MPORT)" \
	  $(wildcard test/$(1)-*.hurl) \
	  $(filter-out \
	    $(patsubst test/$(1)-%.hurl,test/stub-%.hurl,$(wildcard test/$(1)-*.hurl)), \
	    $(wildcard test/stub-*.hurl))
endef

$(foreach b,$(BACKENDS),$(eval $(call BACKEND_RULE,$(b))))

.PHONY: build site dump-endpoints dump-families dump-claims validate-csv validate-tests validate-providers validate-claims validate-builders generate-schema validate-schema dump-capabilities validate-capabilities validate-fixtures test test-unit test-unit-functions test-unit-graphql test-unit-backends test-integration validate-mock test-format test-lint test-coverage clean

build: confusio.com

dump-endpoints: $(REDBEAN_BIN) $(DUMP_ENDPOINTS_SCRIPT) $(INIT_SRCS)
	$(REDBEAN) $(DUMP_ENDPOINTS_SCRIPT)

validate-csv: $(REDBEAN_BIN) $(DUMP_ENDPOINTS_SCRIPT) $(INIT_SRCS)
	$(REDBEAN) $(DUMP_ENDPOINTS_SCRIPT) | python3 scripts/validate-csv.py site/compatibility.csv

validate-tests: $(REDBEAN_BIN) $(DUMP_ENDPOINTS_SCRIPT) $(INIT_SRCS)
	$(REDBEAN) $(DUMP_ENDPOINTS_SCRIPT) | python3 scripts/validate-tests.py $(BACKENDS)

dump-families: $(REDBEAN_BIN) $(DUMP_FAMILIES_SCRIPT) $(INIT_SRCS)
	$(REDBEAN) $(DUMP_FAMILIES_SCRIPT)

validate-providers: $(REDBEAN_BIN) $(DUMP_FAMILIES_SCRIPT) $(INIT_SRCS)
	$(REDBEAN) $(DUMP_FAMILIES_SCRIPT) | python3 scripts/validate-providers.py

dump-claims: $(REDBEAN_BIN) $(DUMP_CLAIMS_SCRIPT) $(BACKEND_SRCS)
	$(REDBEAN) $(DUMP_CLAIMS_SCRIPT) $(BACKENDS)

validate-claims: $(REDBEAN_BIN) $(DUMP_CLAIMS_SCRIPT) $(VALIDATE_CLAIMS_SCRIPT) $(BACKEND_SRCS)
	$(REDBEAN) $(DUMP_CLAIMS_SCRIPT) $(BACKENDS) | $(REDBEAN) $(VALIDATE_CLAIMS_SCRIPT) site/compatibility.csv

validate-builders:
	@if grep -rn 'app\.backend\.rest\s*=' backends/ | grep -v '^Binary'; then \
	  echo "ERROR: backend(s) still use direct app.backend.rest assignment; use make_backend_builder():b:build() instead" >&2; \
	  exit 1; \
	fi
	@if grep -rn 'graphql_resolvers\[' backends/ | grep -v '^Binary'; then \
	  echo "ERROR: backend(s) still use direct graphql_resolvers assignment; use b:graphql() instead" >&2; \
	  exit 1; \
	fi
	@bad=""; \
	for f in backends/*.lua; do \
	  if ! grep -q ':build(' "$$f" && ! grep -q 'dofile' "$$f"; then \
	    bad="$$bad $$f"; \
	  fi; \
	done; \
	if [ -n "$$bad" ]; then \
	  echo "ERROR: backend(s) missing b:build() call (and not an alias that dofiles a root backend):$$bad" >&2; \
	  echo "Every standalone backend must call make_backend_builder() and b:build()." >&2; \
	  exit 1; \
	fi
	@echo "validate-builders OK"

dump-capabilities: $(REDBEAN_BIN) $(DUMP_CAPS_SCRIPT) $(BACKEND_SRCS)
	$(REDBEAN) $(DUMP_CAPS_SCRIPT) $(BACKENDS)

validate-capabilities: $(REDBEAN_BIN) $(DUMP_CAPS_SCRIPT) $(VALIDATE_CAPS_SCRIPT) $(BACKEND_SRCS)
	$(REDBEAN) $(DUMP_CAPS_SCRIPT) $(BACKENDS) | $(REDBEAN) $(VALIDATE_CAPS_SCRIPT)

validate-fixtures:
	python3 scripts/validate-fixtures.py test

generate-schema: $(REDBEAN_BIN) $(GEN_GRAPHQL_SCHEMA_SCRIPT)
	$(REDBEAN) $(GEN_GRAPHQL_SCHEMA_SCRIPT)

validate-schema: $(REDBEAN_BIN) $(GEN_GRAPHQL_SCHEMA_SCRIPT) internal/graphql_schema_data.lua
	$(REDBEAN) $(GEN_GRAPHQL_SCHEMA_SCRIPT) vendor/github-graphql-schema/schema.docs.graphql /tmp/graphql_schema_data_validate.lua
	diff -q internal/graphql_schema_data.lua /tmp/graphql_schema_data_validate.lua

site: $(REDBEAN_BIN) $(DUMP_ENDPOINTS_SCRIPT) $(INIT_SRCS)
	mkdir -p _site
	cp -r site/. _site/
	$(REDBEAN) $(DUMP_ENDPOINTS_SCRIPT) | \
	  python3 scripts/gen-matrix.py - site/compatibility.csv site/index.html _site/index.html

test: test-unit test-integration test-format test-lint validate-csv validate-tests validate-providers validate-claims validate-schema validate-builders validate-capabilities validate-fixtures

# Pure-Lua unit tests (no HTTP server needed): .init.lua functions + GraphQL subsystem
test-unit-functions: $(REDBEAN_BIN) $(INIT_SRCS) $(wildcard test/unit-*.lua)
	$(REDBEAN) test/unit-init.lua
	$(REDBEAN) test/unit-graphql.lua

# Convenience alias: run only the GraphQL unit tests
# unit-graphql.lua is the driver: loads shared state once, then dofiles all sub-files.
test-unit-graphql: $(REDBEAN_BIN) $(INIT_SRCS) $(wildcard test/unit-*.lua)
	$(REDBEAN) test/unit-graphql.lua

# Sequential preamble (boot-path checks), then all backends in parallel
test-unit: test-unit-functions confusio.com $(MOCKS) mock-target.com hurl
	bash test/test-unit.sh
	$(MAKE) -j$$(nproc) test-unit-backends

# Aggregate target — Make runs all prerequisites in parallel under -j
test-unit-backends: $(addprefix test-unit-,$(BACKENDS))

test-integration: | test-unit
test-integration: confusio.com hurl
	bash test/test-integration.sh

validate-mock: mock-gitea.com
	bash test/test-mock-validate.sh

test-format: stylua
	./stylua --check .

test-lint: luacheck
	./luacheck . --exclude-files 'luacov'

test-coverage: $(REDBEAN_BIN) luacov $(INIT_SRCS) $(wildcard test/unit-*.lua)
	rm -f luacov.stats.out luacov.report.out
	COVERAGE=1 $(REDBEAN) test/unit-init.lua
	$(REDBEAN) scripts/luacov-report.lua

clean:
	rm -f redbean.com confusio.com $(MOCKS) mock-target.com hurl stylua luacheck .make-families.mk
	rm -rf _site luacov
