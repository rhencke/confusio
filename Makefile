REDBEAN_VERSION := $(shell cat .redbean-version)
REDBEAN_URL      = https://redbean.dev/redbean-$(REDBEAN_VERSION).com

MOCKS = mock-gitea.com mock-gitlab.com mock-gitbucket.com mock-bitbucket.com \
        mock-harness.com mock-pagure.com mock-onedev.com mock-sourcehut.com \
        mock-radicle.com mock-bitbucket_datacenter.com

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
	@mkdir -p .tmp-mock
	cp test/mock-$*.lua .tmp-mock/.init.lua
	(cd .tmp-mock && zip -u ../$@ .init.lua)
	rm -rf .tmp-mock

.PHONY: build test test-unit test-integration validate-mock clean

build: confusio.com

test: test-unit test-integration

test-unit: confusio.com $(MOCKS) hurl
	bash test/test-unit.sh

test-integration: confusio.com hurl
	bash test/test-integration.sh

validate-mock: mock-gitea.com
	bash test/test-mock-validate.sh

clean:
	rm -f redbean.com confusio.com $(MOCKS) hurl
