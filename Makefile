.PHONY: build run clean app install dmg sign notarize release _create_dmg

# Configuration
APP_NAME := Komet
BUNDLE_ID := com.wickes1.komet
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")

# Signing identity (set via environment or replace with your identity)
# Find yours with: security find-identity -v -p codesigning
SIGNING_IDENTITY ?= -
TEAM_ID ?=

# Paths
BUILD_DIR := .build/release
APP_BUNDLE := $(APP_NAME).app
DMG_NAME := $(APP_NAME)-$(VERSION).dmg

build:
	swift build

run: sign
	open $(APP_BUNDLE)

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
	rm -rf $(DMG_NAME)
	rm -rf dmg-temp

app:
	swift build -c release
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	cp Info.plist $(APP_BUNDLE)/Contents/
	# Inject version from git tag
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(APP_BUNDLE)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(APP_BUNDLE)/Contents/Info.plist
	@echo "Built $(APP_BUNDLE) v$(VERSION)"

# Sign the app (use SIGNING_IDENTITY="-" for ad-hoc signing)
sign: app
	codesign --force --options runtime --entitlements $(APP_NAME).entitlements \
		--sign "$(SIGNING_IDENTITY)" $(APP_BUNDLE)
	codesign --verify --verbose $(APP_BUNDLE)
	@echo "Signed $(APP_BUNDLE)"

# Helper to create DMG (internal use)
_create_dmg:
	rm -rf dmg-temp $(DMG_NAME)
	mkdir -p dmg-temp
	cp -r $(APP_BUNDLE) dmg-temp/
	ln -s /Applications dmg-temp/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder dmg-temp \
		-ov -format UDZO $(DMG_NAME)
	rm -rf dmg-temp

# Create signed DMG
dmg: sign _create_dmg
	@echo "Created $(DMG_NAME)"

# Sign the DMG (required for notarization)
sign-dmg: dmg
	codesign --force --sign "$(SIGNING_IDENTITY)" $(DMG_NAME)
	@echo "Signed $(DMG_NAME)"

# Notarize (requires Apple Developer account and app-specific password)
# Set APPLE_ID and APPLE_TEAM_ID environment variables
notarize: sign-dmg
	xcrun notarytool submit $(DMG_NAME) \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(TEAM_ID)" \
		--password "$(APPLE_APP_PASSWORD)" \
		--wait
	xcrun stapler staple $(DMG_NAME)
	@echo "Notarized and stapled $(DMG_NAME)"

# Full release build (unsigned - for CI to sign)
release: app _create_dmg
	@echo "Created $(DMG_NAME) (unsigned)"

# Create ZIP for GitHub release (alternative to DMG)
zip: sign
	rm -f $(APP_NAME)-$(VERSION).zip
	ditto -c -k --keepParent $(APP_BUNDLE) $(APP_NAME)-$(VERSION).zip
	@echo "Created $(APP_NAME)-$(VERSION).zip"

install: app
	cp -r $(APP_BUNDLE) /Applications/
	@echo "Installed to /Applications/$(APP_BUNDLE)"

# Calculate SHA256 for Homebrew formula
sha256:
	@shasum -a 256 $(DMG_NAME) | cut -d ' ' -f 1
