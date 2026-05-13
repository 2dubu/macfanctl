PREFIX     ?= /usr/local
BIN         = macfanctl
BUILD_DIR   = .build/apple/Products/Release
BUILD       = $(BUILD_DIR)/$(BIN)

.PHONY: build test sign install uninstall sudoers clean run-list

build:
	swift build -c release --arch arm64 --arch x86_64

test:
	swift test

sign: build
	codesign --force --sign - --options runtime $(BUILD)

install: sign
	sudo install -m 755 -o root -g wheel $(BUILD) $(PREFIX)/bin/$(BIN)
	@echo "Installed to $(PREFIX)/bin/$(BIN)"
	@echo "Run 'make sudoers' to enable passwordless invocation"

sudoers:
	@echo "$$USER ALL=(root) NOPASSWD: $(PREFIX)/bin/$(BIN)" | \
	  sudo tee /etc/sudoers.d/macfanctl > /dev/null
	@sudo chmod 440 /etc/sudoers.d/macfanctl
	@sudo visudo -c -f /etc/sudoers.d/macfanctl && echo "sudoers rule installed"

uninstall:
	sudo rm -f $(PREFIX)/bin/$(BIN) /etc/sudoers.d/macfanctl

run-list:
	swift run macfanctl list

clean:
	swift package clean
