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

redbean.com: .redbean-version
	wget -q $(REDBEAN_URL) -O redbean.com
	chmod +x redbean.com

hurl: .hurl-version
ifneq (,$(or $(findstring MINGW,$(HURL_OS)),$(findstring MSYS,$(HURL_OS)),$(findstring CYGWIN,$(HURL_OS))))
	curl -sL $(HURL_URL) -o hurl.zip
	unzip -p hurl.zip hurl-$(HURL_VERSION)-$(HURL_PLATFORM)/bin/hurl.exe > hurl
	chmod +x hurl
	rm hurl.zip
else
	curl -sL $(HURL_URL) | tar -xz --strip-components=2 hurl-$(HURL_VERSION)-$(HURL_PLATFORM)/bin/hurl
	chmod +x hurl
endif

confusio.com: redbean.com .init.lua $(wildcard backends/*.lua)
	cp redbean.com confusio.com
	zip confusio.com .init.lua $(wildcard backends/*.lua)

mock-%.com: redbean.com test/mock-%.lua
	cp redbean.com $@
	@mkdir -p .tmp-mock-$*
	cp test/mock-$*.lua .tmp-mock-$*/.init.lua
	(cd .tmp-mock-$* && zip -u ../$@ .init.lua)
	rm -rf .tmp-mock-$*

# Backend test configuration.
# To add a backend: append to BACKENDS (ports auto-assigned from 18080).
# Each backend needs test/mock-<name>.lua (symlink ok) and
# test/<name>-repos.hurl + test/<name>-users.hurl (symlinks ok).
BACKENDS = azuredevops bitbucket bitbucket_datacenter codeberg forgejo gerrit gitbucket gitea gitlab gogs \
           harness kallithea launchpad notabug onedev pagure phabricator radicle \
           rhodecode sourceforge sourcehut
MOCKS    = $(addprefix mock-,$(addsuffix .com,$(BACKENDS)))

gitea_HURL = test/gitea-root-auth.hurl test/gitea-repos.hurl \
             test/gitea-repos-ext.hurl test/gitea-users.hurl

# Stub providers share the same mock and split their tests across per-category files.
STUB_HURL = test/$(1)-repos.hurl test/$(1)-teams.hurl test/$(1)-security-advisories.hurl test/$(1)-users.hurl
kallithea_HURL   = $(call STUB_HURL,kallithea)
launchpad_HURL   = $(call STUB_HURL,launchpad)
phabricator_HURL = $(call STUB_HURL,phabricator)
rhodecode_HURL   = $(call STUB_HURL,rhodecode)
sourceforge_HURL = $(call STUB_HURL,sourceforge)

$(eval _p := 18080)
$(foreach b,$(BACKENDS),$(eval $(b)_CPORT := $(_p))$(eval $(b)_MPORT := $(shell expr $(_p) + 1))$(eval _p := $(shell expr $(_p) + 2)))

define BACKEND_RULE
.PHONY: test-unit-$(1)
test-unit-$(1): confusio.com mock-$(1).com hurl
	bash test/run-backend.sh mock-$(1).com \
	  $($(1)_CPORT) $($(1)_MPORT) \
	  "-- $(1) http://127.0.0.1:$($(1)_MPORT)" \
	  $(or $($(1)_HURL),test/$(1)-repos.hurl test/$(1)-users.hurl)
endef

$(foreach b,$(BACKENDS),$(eval $(call BACKEND_RULE,$(b))))

.PHONY: build site test test-unit test-unit-backends test-integration validate-mock clean

build: confusio.com

site:
	mkdir -p _site
	cp -r site/. _site/
	python3 scripts/gen-matrix.py site/compatibility.csv site/index.html _site/index.html

test: test-unit test-integration

# Sequential preamble (boot-path checks), then all backends in parallel
test-unit: confusio.com $(MOCKS) hurl
	bash test/test-unit.sh
	$(MAKE) -j$$(nproc) test-unit-backends

# Aggregate target — Make runs all prerequisites in parallel under -j
test-unit-backends: $(addprefix test-unit-,$(BACKENDS))

test-integration: confusio.com hurl
	bash test/test-integration.sh

validate-mock: mock-gitea.com
	bash test/test-mock-validate.sh

clean:
	rm -f redbean.com confusio.com $(MOCKS) hurl
	rm -rf _site
