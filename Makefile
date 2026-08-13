PREFIX     ?= /usr/local
BIN         = macfanctl
BUILD_DIR   = .build/apple/Products/Release
BUILD       = $(BUILD_DIR)/$(BIN)

.PHONY: build test sign install uninstall setup raycast_setup clean run-list

build:
	swift build -c release --arch arm64 --arch x86_64

test:
	swift test

sign: build
	codesign --force --sign - --options runtime $(BUILD)

install: sign
	sudo install -m 755 -o root -g wheel $(BUILD) $(PREFIX)/bin/$(BIN)
	@echo "Installed to $(PREFIX)/bin/$(BIN)"
	@echo "Run 'sudo $(BIN) setup' (or 'make setup') to register NOPASSWD sudoers rule"

setup:
	sudo $(PREFIX)/bin/$(BIN) setup

raycast_setup:
	$(PREFIX)/bin/$(BIN) raycast setup

uninstall:
	-sudo $(PREFIX)/bin/$(BIN) setup --uninstall 2>/dev/null
	sudo rm -f $(PREFIX)/bin/$(BIN)

run-list:
	swift run macfanctl list

clean:
	swift package clean
