# Moves — menu-bar task tracker
#
# Quick start:
#   make           # debug-builds via SwiftPM into ./build/Moves.app
#   make run       # build + launch
#   make check     # compile only, no bundling/signing (agent / CI gate)
#   make install   # copy to /Applications/ and register with LaunchServices
#   make help      # full target list
#
# Build is driven by `swift build` + ./build.sh — NO Xcode IDE, NO
# xcodebuild, NO XcodeGen. Xcode is only a toolchain provider (swift /
# codesign). Adapted from the DJRoomba build environment.

CONFIG       := debug
APP          := build/Moves.app
LSREGISTER   := /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
MIN_MACOS    := 14
MIN_SWIFT    := 6.0

APP_NAME      := Moves
ENTITLEMENTS  := Moves/Moves.entitlements

# Dev signing identity (used by ./build.sh). Falls back to ad-hoc ("-") if
# the named identity is missing — fine for `make run` on your own machine.
DEV_IDENTITY  ?= Apple Development: Thomas Ptacek (7F2QE7P59D)

PROVISION_PROFILE ?=

.PHONY: all deps build check test release run clean install uninstall register help

all: build

help:
	@echo "Build:"
	@echo "  make / build      Build $(CONFIG) into ./$(APP)  (default)"
	@echo "  check             Compile only (swift build) — no bundle/sign; CI/agent gate"
	@echo "  test              Run the SwiftPM test suite (sanity round-trips)"
	@echo "  release           Build release into ./$(APP)"
	@echo "  run               Build and launch Moves"
	@echo "  clean             Remove ./build/ ./.build/"
	@echo "  deps              Verify build prerequisites (auto-run before build)"
	@echo ""
	@echo "Local install:"
	@echo "  install           Copy Moves.app to /Applications/ and register it"
	@echo "  uninstall         Remove /Applications/Moves.app"
	@echo "  register          Refresh LaunchServices for ./$(APP)"
	@echo ""
	@echo "  help              Show this message"

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

deps:
	@echo "→ Checking build prerequisites..."
	@OS_VERSION=$$(sw_vers -productVersion 2>/dev/null); \
	if [ -z "$$OS_VERSION" ]; then \
	  echo "  ✗ Could not detect macOS version. Moves only builds on macOS."; exit 1; \
	fi; \
	OS_MAJOR=$$(echo $$OS_VERSION | cut -d. -f1); \
	if [ $$OS_MAJOR -lt $(MIN_MACOS) ]; then \
	  echo "  ✗ macOS $$OS_VERSION — Moves requires macOS $(MIN_MACOS).0 or newer."; exit 1; \
	fi; \
	echo "  ✓ macOS $$OS_VERSION"
	@command -v swift >/dev/null 2>&1 || { \
	  echo "  ✗ swift not on PATH. Install Xcode (App Store) or the Swift toolchain"; \
	  echo "    from https://swift.org/install/macos/, then re-run."; exit 1; }
	@SW_LINE=$$(swift --version 2>&1 | head -1); \
	echo "  ✓ $$SW_LINE"
	@[ -f Package.swift ] || { echo "  ✗ Package.swift not found. Run make from the repo root."; exit 1; }
	@echo "  ✓ Package.swift present"
	@[ -x ./build.sh ] || { echo "  ✗ ./build.sh missing or not executable."; exit 1; }
	@echo "  ✓ build.sh present"
	@echo "→ Prerequisites OK."

# ---------------------------------------------------------------------------
# Build (delegates to ./build.sh: swift build + bundle + codesign)
# ---------------------------------------------------------------------------

build: deps
	SIGN_IDENTITY="$(DEV_IDENTITY)" PROVISION_PROFILE="$(PROVISION_PROFILE)" ./build.sh $(CONFIG)

release: deps
	SIGN_IDENTITY="$(DEV_IDENTITY)" PROVISION_PROFILE="$(PROVISION_PROFILE)" ./build.sh release

# Compile-only gate — no .app, no signing. CI / agent verification.
check: deps
	swift build -c $(CONFIG)
	@echo "✓ compiles ($(CONFIG))"

# Run the test suite. Phase 1 ships round-trip tests for every repository.
test: deps
	swift test
	@echo "✓ tests pass"

# ---------------------------------------------------------------------------
# Run / install / register
# ---------------------------------------------------------------------------

run: build
	open "$(APP)"

install: build
	@if [ ! -d "$(APP)" ]; then echo "✗ $(APP) missing — build failed?"; exit 1; fi
	rm -rf /Applications/Moves.app
	cp -R "$(APP)" /Applications/
	@echo "✓ copied to /Applications/Moves.app"
	$(LSREGISTER) -f /Applications/Moves.app
	@echo "✓ registered /Applications/Moves.app with LaunchServices"

uninstall:
	@if [ -d /Applications/Moves.app ]; then \
	  rm -rf /Applications/Moves.app 2>/dev/null || sudo rm -rf /Applications/Moves.app; \
	  echo "✓ removed /Applications/Moves.app"; \
	else \
	  echo "  (no /Applications/Moves.app to remove)"; \
	fi

register: build
	$(LSREGISTER) -f "$(APP)"
	@echo "✓ registered $(APP) with LaunchServices"

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

clean:
	rm -rf build .build
	@echo "✓ removed build/ and .build/"
