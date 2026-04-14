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

redbean.com: .redbean-version
	curl -fsSL $(REDBEAN_URL) -o redbean.com
	chmod +x redbean.com

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

confusio.com: redbean.com .init.lua $(wildcard backends/*.lua)
	cp redbean.com confusio.com
	zip confusio.com .init.lua $(wildcard backends/*.lua)

mock-%.com: redbean.com test/mock-%.lua
	cp redbean.com $@
	@mkdir -p .tmp-mock-$*
	cp test/mock-$*.lua .tmp-mock-$*/.init.lua
	(cd .tmp-mock-$* && zip -u ../$@ .init.lua)
	rm -rf .tmp-mock-$*

# Family-alias mock rules: build mock-<alias>.com from the root family's mock lua
# instead of a per-alias test/mock-<alias>.lua.  Explicit rules take precedence over
# the mock-%.com pattern rule above.
# ALIAS_MOCK_RULE(alias, root): builds mock-<alias>.com from test/mock-<root>.lua
define ALIAS_MOCK_RULE
mock-$(1).com: redbean.com test/mock-$(2).lua
	cp redbean.com $$@
	@mkdir -p .tmp-mock-$(1)
	cp test/mock-$(2).lua .tmp-mock-$(1)/.init.lua
	(cd .tmp-mock-$(1) && zip -u ../$$@ .init.lua)
	rm -rf .tmp-mock-$(1)
endef

# Gitea-family aliases — must match provider_families["gitea"].aliases in .init.lua.
# validate-providers will catch any mismatch.
GITEA_FAMILY_ALIASES := codeberg forgejo gogs notabug
$(foreach a,$(GITEA_FAMILY_ALIASES),$(eval $(call ALIAS_MOCK_RULE,$(a),gitea)))

# Backend test configuration.
# To add a standalone backend: append to BACKENDS (ports auto-assigned from 18080).
# Each backend needs test/mock-<name>.lua and at least one test/<name>-*.hurl file
# (symlinks ok — used by wildcard discovery).
# To add a family-alias backend: add to BACKENDS and to the appropriate FAMILY_ALIASES
# list above; no test/mock-<name>.lua needed.
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

.PHONY: build site dump-endpoints validate-csv validate-tests test test-unit test-unit-functions test-unit-backends test-integration validate-mock test-format test-lint test-coverage clean

build: confusio.com

dump-endpoints: redbean.com
	./redbean.com -i scripts/dump-endpoints.lua

validate-csv: redbean.com
	./redbean.com -i scripts/dump-endpoints.lua 2>/dev/null | python3 scripts/validate-csv.py site/compatibility.csv

validate-tests: redbean.com
	./redbean.com -i scripts/dump-endpoints.lua 2>/dev/null | python3 scripts/validate-tests.py $(BACKENDS)

site: redbean.com
	mkdir -p _site
	cp -r site/. _site/
	./redbean.com -i scripts/dump-endpoints.lua 2>/dev/null | \
	  python3 scripts/gen-matrix.py - site/compatibility.csv site/index.html _site/index.html

test: test-unit test-integration test-format test-lint validate-csv validate-tests

# Unit tests for .init.lua global functions (pure Lua, no HTTP server needed)
test-unit-functions: redbean.com
	./redbean.com -i test/unit-init.lua

# Sequential preamble (boot-path checks), then all backends in parallel
test-unit: test-unit-functions confusio.com $(MOCKS) hurl
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

test-coverage: redbean.com luacov
	rm -f luacov.stats.out luacov.report.out
	COVERAGE=1 ./redbean.com -i test/unit-init.lua
	./redbean.com -i scripts/luacov-report.lua

clean:
	rm -f redbean.com confusio.com $(MOCKS) hurl stylua luacheck
	rm -rf _site luacov
