# DJ Roomba — playlist-forward, local-first MusicKit player
#
# Quick start:
#   make           # debug-builds via SwiftPM into ./build/DJRoomba.app
#   make run       # build + launch
#   make check     # compile only, no bundling/signing (agent / CI gate)
#   make install   # copy to /Applications/ and register with LaunchServices
#   make help      # full target list
#
# Build is driven by `swift build` + ./build.sh — NO Xcode IDE, NO
# xcodebuild, NO XcodeGen. Xcode is only a toolchain provider (swift /
# codesign / notarytool / stapler), and only `make dist` reaches for the
# Developer ID + notary parts. Cloned from the tqbf/mdv build environment.

CONFIG       := debug
APP          := build/DJRoomba.app
LSREGISTER   := /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
MIN_MACOS    := 14
MIN_SWIFT    := 6.0

# ---------------------------------------------------------------------------
# Release variables
# ---------------------------------------------------------------------------
# `dist` enforces an exact tag (`vX.Y.Z`) so we never ship `0.1.0` from a
# commit that's merely *near* the tag. Override VERSION=... for one-off
# release-target testing without tagging first.
APP_NAME      := DJRoomba
VERSION       ?= $(shell git describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null | sed 's/^v//')
DIST_DIR      := dist
NOTARY_ZIP    := $(DIST_DIR)/$(APP_NAME)-$(VERSION)-notary.zip
RELEASE_ZIP   := $(DIST_DIR)/$(APP_NAME)-$(VERSION)-macos.zip
ENTITLEMENTS  := DJRoomba/DJRoomba.entitlements

# Dev signing identity (used by ./build.sh). Apple Development — NOT adhoc:
# an adhoc MusicKit build returns an empty library (roadmap Phase 1).
DEV_IDENTITY  ?= Apple Development: Thomas Ptacek (7F2QE7P59D)

# Distribution signing. Developer ID + hardened runtime + notarization, the
# mdv pipeline. Substring-matches the CN, so the team id alone also works.
TEAM_ID       ?= KK7E9G89GW
CERT_NAME     ?= Developer ID Application: Thomas Ptacek ($(TEAM_ID))

# Notarization credentials profile. Populate it once with `make
# notary-setup` (interactive; never puts the password on the cmdline).
NOTARY_PROFILE ?= djroomba-notary

# OPEN RISK (roadmap Phase 2/3): a notarized Developer ID build may need an
# embedded MusicKit-App-Service provisioning profile for Apple Music
# *catalog* APIs. Phase 1 proved library read/playback needs none. When
# resolved, set PROVISION_PROFILE=/path/to.provisionprofile — build.sh
# embeds it and `sign` re-signs against it. Until then it is a no-op.
PROVISION_PROFILE ?=

NOTES_FILE    ?=

.PHONY: all deps build check release run clean install uninstall register help \
        check-version notary-setup sign zip-notary notarize staple zip-release \
        checksum verify-release dist github-release

all: build

help:
	@echo "Build:"
	@echo "  make / build      Build $(CONFIG) into ./$(APP)  (default)"
	@echo "  check             Compile only (swift build) — no bundle/sign; CI/agent gate"
	@echo "  release           Build release into ./$(APP)"
	@echo "  run               Build and launch DJ Roomba"
	@echo "  clean             Remove ./build/ ./.build/ ./dist/"
	@echo "  deps              Verify build prerequisites (auto-run before build)"
	@echo ""
	@echo "Local install:"
	@echo "  install           Copy DJRoomba.app to /Applications/ and register it"
	@echo "  uninstall         Remove /Applications/DJRoomba.app"
	@echo "  register          Refresh LaunchServices for ./$(APP)"
	@echo ""
	@echo "Release pipeline (require an exact 'vX.Y.Z' git tag):"
	@echo "  notary-setup      One-time: store notary creds in keychain ($(NOTARY_PROFILE))"
	@echo "  dist              Build → sign → notarize → staple → zip → checksum"
	@echo "  github-release    Upload \$$(RELEASE_ZIP) + .sha256 to a GitHub release"
	@echo "  sign              codesign Developer ID + hardened runtime + timestamp"
	@echo "  notarize          Submit to Apple (keychain profile $(NOTARY_PROFILE))"
	@echo "  staple            xcrun stapler staple"
	@echo "  verify-release    spctl + codesign sanity-check the bundle"
	@echo ""
	@echo "  help              Show this message"

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

deps:
	@echo "→ Checking build prerequisites..."
	@OS_VERSION=$$(sw_vers -productVersion 2>/dev/null); \
	if [ -z "$$OS_VERSION" ]; then \
	  echo "  ✗ Could not detect macOS version. DJ Roomba only builds on macOS."; exit 1; \
	fi; \
	OS_MAJOR=$$(echo $$OS_VERSION | cut -d. -f1); \
	if [ $$OS_MAJOR -lt $(MIN_MACOS) ]; then \
	  echo "  ✗ macOS $$OS_VERSION — DJ Roomba requires macOS $(MIN_MACOS).0 or newer."; exit 1; \
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
# Build (delegates to ./build.sh: swift build + bundle + Apple Dev sign)
# ---------------------------------------------------------------------------

build: deps
	SIGN_IDENTITY="$(DEV_IDENTITY)" PROVISION_PROFILE="$(PROVISION_PROFILE)" ./build.sh $(CONFIG)

release: deps
	SIGN_IDENTITY="$(DEV_IDENTITY)" PROVISION_PROFILE="$(PROVISION_PROFILE)" ./build.sh release

# Compile-only gate — no .app, no signing. Replaces the retired
# `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` agent/CI verification.
check: deps
	swift build -c $(CONFIG)
	@echo "✓ compiles ($(CONFIG))"

# ---------------------------------------------------------------------------
# Run / install / register
# ---------------------------------------------------------------------------

run: build
	open "$(APP)"

install: build
	@if [ ! -d "$(APP)" ]; then echo "✗ $(APP) missing — build failed?"; exit 1; fi
	rm -rf /Applications/DJRoomba.app
	cp -R "$(APP)" /Applications/
	@echo "✓ copied to /Applications/DJRoomba.app"
	$(LSREGISTER) -f /Applications/DJRoomba.app
	@echo "✓ registered /Applications/DJRoomba.app with LaunchServices"

uninstall:
	@if [ -d /Applications/DJRoomba.app ]; then \
	  rm -rf /Applications/DJRoomba.app 2>/dev/null || sudo rm -rf /Applications/DJRoomba.app; \
	  echo "✓ removed /Applications/DJRoomba.app"; \
	else \
	  echo "  (no /Applications/DJRoomba.app to remove)"; \
	fi

register: build
	$(LSREGISTER) -f "$(APP)"
	@echo "✓ registered $(APP) with LaunchServices"

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

clean:
	rm -rf build .build $(DIST_DIR)
	@echo "✓ removed build/, .build/, and $(DIST_DIR)/"

# ---------------------------------------------------------------------------
# Release pipeline: sign → zip-notary → notarize → staple → zip-release →
# checksum → verify-release. The two-zip dance is on purpose: Apple's notary
# service operates on a zip; stapling writes the ticket back into the .app;
# the zip we distribute must be a fresh one taken AFTER stapling so offline
# first-launch Gatekeeper finds the ticket inside the bundle.
#
#   git tag v0.1.0 && make dist
# ---------------------------------------------------------------------------

dist: check-version clean release sign zip-notary notarize staple zip-release checksum verify-release
	@echo "✓ release artifact ready: $(RELEASE_ZIP)"
	@echo "  next: make github-release   (or upload $(RELEASE_ZIP) manually)"

check-version:
	@if [ -z "$(VERSION)" ]; then \
	  echo "✗ releases must be built from an exact git tag, e.g.  git tag v0.1.0 && make dist"; \
	  echo "  (override with VERSION=... on the command line for one-off testing)"; \
	  exit 1; \
	fi
	@echo "→ release version $(VERSION)"

# One-time setup before the first `make dist` (re-run to rotate). Stores
# the notary credentials in the login keychain under $(NOTARY_PROFILE) so
# the pipeline never sees the password. Interactive: notarytool prompts
# (hidden) for the app-specific password — create one at
# https://appleid.apple.com → Sign-In and Security → App-Specific
# Passwords. Pass APPLE_ID=you@example.com to skip the Apple ID prompt.
# The password is NEVER passed on the command line (no shell history /
# process-list leak).
notary-setup:
	@command -v xcrun >/dev/null 2>&1 || { echo "✗ xcrun not found — install Xcode or the Command Line Tools"; exit 1; }
	@if [ ! -t 0 ]; then \
	  echo "✗ make notary-setup is interactive — run it in a real terminal,"; \
	  echo "  not from an editor / agent shell (it prompts for your password)."; \
	  exit 1; \
	fi
	@echo "→ storing notary credentials in keychain profile '$(NOTARY_PROFILE)' (team $(TEAM_ID))"
	xcrun notarytool store-credentials "$(NOTARY_PROFILE)" \
	  --team-id "$(TEAM_ID)" \
	  $(if $(APPLE_ID),--apple-id "$(APPLE_ID)",)
	@echo "✓ stored. 'make dist' / 'make notarize' will use profile '$(NOTARY_PROFILE)'."

# `--options runtime` (hardened runtime, required by notarization),
# `--timestamp` (Apple TSA — signature outlives cert expiry),
# `--entitlements` (the sandbox app needs them re-applied on re-sign).
sign: release
	@if [ -z "$(CERT_NAME)" ]; then echo "✗ CERT_NAME required"; exit 1; fi
	@security find-certificate -c "Developer ID Certification Authority" >/dev/null 2>&1 \
	  || security find-certificate -c "Developer ID Certification Authority" /Library/Keychains/System.keychain >/dev/null 2>&1 \
	  || { \
	    echo "✗ Apple's 'Developer ID Certification Authority' intermediate is missing from your keychains."; \
	    echo "  codesign can't build a chain to a trusted root without it."; \
	    echo "  Fix: download the G2 intermediate from https://www.apple.com/certificateauthority/"; \
	    echo "  and double-click the .cer to install it into your login keychain."; \
	    exit 1; \
	  }
	@echo "→ signing $(APP) as $(CERT_NAME)"
	codesign --force --options runtime --timestamp \
	  --entitlements "$(ENTITLEMENTS)" \
	  --sign "$(CERT_NAME)" "$(APP)"
	codesign --verify --strict --verbose=2 "$(APP)"

zip-notary: sign
	@mkdir -p "$(DIST_DIR)"
	rm -f "$(NOTARY_ZIP)"
	ditto -c -k --keepParent "$(APP)" "$(NOTARY_ZIP)"
	@echo "✓ wrote $(NOTARY_ZIP)"

notarize: zip-notary
	@if [ -z "$(NOTARY_PROFILE)" ]; then \
	  echo "✗ NOTARY_PROFILE is empty. Run 'make notary-setup' once first."; \
	  exit 1; \
	fi
	@echo "→ submitting $(NOTARY_ZIP) via profile '$(NOTARY_PROFILE)' (a few minutes)"
	xcrun notarytool submit "$(NOTARY_ZIP)" \
	  --keychain-profile "$(NOTARY_PROFILE)" \
	  --wait

staple: notarize
	xcrun stapler staple "$(APP)"
	xcrun stapler validate "$(APP)"

zip-release: staple
	rm -f "$(RELEASE_ZIP)"
	ditto -c -k --keepParent "$(APP)" "$(RELEASE_ZIP)"
	@echo "✓ wrote $(RELEASE_ZIP)"

checksum: zip-release
	cd "$(DIST_DIR)" && shasum -a 256 "$$(basename $(RELEASE_ZIP))" > "$$(basename $(RELEASE_ZIP)).sha256"
	@echo "✓ wrote $(RELEASE_ZIP).sha256"

# spctl confirms the stapled bundle passes Gatekeeper without phoning Apple.
verify-release: zip-release
	spctl --assess --type execute --verbose "$(APP)"
	codesign --verify --deep --strict --verbose=2 "$(APP)"

# Upload artifacts to a GitHub release. Independent of `dist` so a failed
# upload can be retried without re-notarizing.
github-release:
	@if ! command -v gh >/dev/null 2>&1; then echo "✗ gh CLI not installed (brew install gh)"; exit 1; fi
	@if [ -z "$(VERSION)" ]; then echo "✗ VERSION required (tag or override)"; exit 1; fi
	@if [ ! -f "$(RELEASE_ZIP)" ]; then echo "✗ $(RELEASE_ZIP) not found — run make dist first"; exit 1; fi
	@if [ ! -f "$(RELEASE_ZIP).sha256" ]; then echo "✗ $(RELEASE_ZIP).sha256 not found — run make dist first"; exit 1; fi
	gh release create "v$(VERSION)" \
	  "$(RELEASE_ZIP)" \
	  "$(RELEASE_ZIP).sha256" \
	  --title "$(APP_NAME) $(VERSION)" \
	  $(if $(NOTES_FILE),--notes-file "$(NOTES_FILE)",--generate-notes)
	@echo "✓ published v$(VERSION)"
