# fenêtre — build & bundle
#
# A real .app bundle is required for macOS to reliably surface fenêtre in the
# Accessibility permission list (bare command-line binaries don't show up).
#
# NOTE: keep comments on their own lines — a trailing comment after a `:=`
# assignment leaks the whitespace before the `#` into the variable value.

# SwiftPM product / inner executable name
APP_NAME    := fenetre
# .app bundle name
BUNDLE_NAME := Fenetre
BUNDLE_ID   := com.joris.fenetre
CONFIG      ?= debug

# Code-signing identity. We sign with the self-signed `fenetre-dev` cert so the
# Accessibility grant sticks across rebuilds — a stable code-signing identity
# keeps the same TCC "designated requirement". Fall back to ad-hoc with:
#   make run CODESIGN_ID="-"
CODESIGN_ID ?= fenetre-dev

APP      := $(BUNDLE_NAME).app
CONTENTS := $(APP)/Contents
MACOS    := $(CONTENTS)/MacOS
BIN      := .build/$(CONFIG)/$(APP_NAME)

.PHONY: build bundle run logs kill clean

# build  — compile the Swift package
build:
	swift build -c $(CONFIG)

# bundle — assemble and sign $(APP)
bundle: build
	@rm -rf "$(APP)"
	@mkdir -p "$(MACOS)"
	@cp "$(BIN)" "$(MACOS)/$(APP_NAME)"
	@cp Info.plist "$(CONTENTS)/Info.plist"
	@codesign --force --sign "$(CODESIGN_ID)" --identifier "$(BUNDLE_ID)" "$(APP)"
	@echo "✔ Built $(APP)  (signed: $(CODESIGN_ID))"

# run    — build the bundle and launch it (detached; use for normal use)
run: bundle kill
	@open "$(APP)"
	@echo "✔ Launched. Look for the menu-bar icon; hold ⌥ and tap Tab to switch."

# logs   — launch via LaunchServices (so Accessibility applies) and tail the
#          log file. Ctrl-C stops the tail; the app keeps running.
logs: bundle kill
	@open "$(APP)"
	@sleep 1
	@echo "── tailing /tmp/fenetre.log  (Ctrl-C stops tailing; app keeps running) ──"
	@tail -F /tmp/fenetre.log

# kill   — terminate any running fenêtre instance (prevents stale duplicates)
kill:
	@killall $(APP_NAME) 2>/dev/null && echo "killed running fenêtre" || true

# clean  — remove the bundle and build artifacts
clean:
	rm -rf "$(APP)" .build
