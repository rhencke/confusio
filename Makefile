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

confusio.com: redbean.com .init.lua
	cp redbean.com confusio.com
	zip confusio.com .init.lua

.PHONY: build test clean

build: confusio.com

test: confusio.com hurl
	bash test/test.sh

clean:
	rm -f redbean.com confusio.com hurl
