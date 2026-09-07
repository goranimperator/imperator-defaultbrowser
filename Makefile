APP_NAME    = Imperator DefaultBrowser
BINARY_NAME = DefaultBrowser
BUNDLE      = build/$(APP_NAME).app
DIST        = dist
ZIP         = $(DIST)/Imperator-DefaultBrowser-$(VERSION).zip
BUILD_NUMBER = $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
RELEASE_BRANCH = main

# Self-signed identity, not ad-hoc. The app registers a login item through
# SMAppService, and that registration is keyed to the bundle's designated
# requirement. Ad-hoc signing mints a new cdhash on every build, so every
# update would look like a different app and drop the login item. The
# Imperator Dev cert keeps the requirement stable across releases.
CODESIGN_IDENTITY ?= Imperator Dev

.PHONY: all build clean run install verify dist release check-version check-release icon

all: build

build:
	swift build -c release
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp ".build/release/$(BINARY_NAME)" "$(BUNDLE)/Contents/MacOS/$(BINARY_NAME)"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"
	codesign --force --sign "$(CODESIGN_IDENTITY)" "$(BUNDLE)"
	@echo "Built: $(BUNDLE)"

install: build
	@pkill -x $(BINARY_NAME) 2>/dev/null || true
	@sleep 0.5
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(BUNDLE)" "/Applications/$(APP_NAME).app"
	@echo "Installed: /Applications/$(APP_NAME).app"
	open "/Applications/$(APP_NAME).app"

run: build
	open "$(BUNDLE)"

# Every runnable acceptance gate, in the order GATES.md lists them. Not a
# dependency of release: verify-launch needs no instance of the app running, and
# failing a release because the app happens to be open would be its own trap.
# Run this first, by hand, then cut the release.
verify: build
	@pkill -x $(BINARY_NAME) 2>/dev/null || true
	@sleep 0.5
	codesign --verify --strict "$(BUNDLE)"
	node tools/verify-discovery.mjs
	node tools/verify-default-detection.mjs
	node tools/verify-order.mjs
	node tools/verify-brand.mjs
	node tools/verify-launch.mjs
	node tools/verify-icon.mjs
	node tools/verify-selftest.mjs
	node tools/verify-hygiene.mjs
	node tools/verify-release.mjs
	@echo "All runnable gates passed. GATES.md G9 and G10 are manual."

# Resources/AppIcon.icns is the artwork itself and is checked in, so there is
# nothing to generate it from. This target only re-cuts the README preview from
# it, which is what keeps the two in sync after the artwork is replaced.
icon:
	@mkdir -p build/icon
	iconutil -c iconset Resources/AppIcon.icns -o build/icon/AppIcon.iconset
	sips -s format png -z 128 128 build/icon/AppIcon.iconset/icon_256x256.png --out Resources/AppIcon.png
	@rm -rf build/icon
	@echo "Re-cut Resources/AppIcon.png from Resources/AppIcon.icns"

clean:
	rm -rf build dist

check-version:
	@test -n "$(VERSION)" || { echo "Usage: make $(MAKECMDGOALS) VERSION=1.0.0"; exit 1; }

# Everything release needs, checked before it changes anything. release makes a
# commit before it tags, so a tag that already exists or a missing gh would
# otherwise leave a "Release vX" commit behind with nothing pointing at it.
check-release: check-version
	@command -v gh >/dev/null || { echo "gh is not installed. brew install gh, then gh auth login."; exit 1; }
	@git diff --quiet && git diff --cached --quiet || { echo "Working tree dirty. Commit first."; exit 1; }
	@test "$$(git rev-parse --abbrev-ref HEAD)" = "$(RELEASE_BRANCH)" || \
		{ echo "On $$(git rev-parse --abbrev-ref HEAD), not $(RELEASE_BRANCH). Releases are cut from $(RELEASE_BRANCH)."; exit 1; }
	@git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null && \
		{ echo "Tag v$(VERSION) already exists."; exit 1; } || true
	@gh release view "v$(VERSION)" >/dev/null 2>&1 && \
		{ echo "Release v$(VERSION) already published."; exit 1; } || true

# Build a distributable zip. Safe: touches nothing in git, nothing on the remote.
#
# The version is stamped into the BUILT bundle rather than the source, so a test
# zip reports the version it would ship as without dirtying the working tree.
# Editing Info.plist breaks the signature, hence the re-sign.
dist: check-version build
	@mkdir -p $(DIST)
	rm -f "$(ZIP)"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(BUNDLE)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" "$(BUNDLE)/Contents/Info.plist"
	codesign --force --sign "$(CODESIGN_IDENTITY)" "$(BUNDLE)"
	ditto -c -k --sequesterRsrc --keepParent "$(BUNDLE)" "$(ZIP)"
	@echo "Packaged: $(ZIP)"

# Bump version, commit, tag, push, publish the GitHub release with the zip attached.
release: check-release
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" Resources/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" Resources/Info.plist
	$(MAKE) dist VERSION=$(VERSION)
	git add Resources/Info.plist
	git commit -m "Release v$(VERSION)"
	git tag -a v$(VERSION) -m "$(APP_NAME) $(VERSION)"
	git push origin $(RELEASE_BRANCH)
	git push origin v$(VERSION)
	gh release create v$(VERSION) \
		--title "$(APP_NAME) $(VERSION)" \
		--notes "Switch the default web browser from the menu bar. Every installed browser gets its own row; click one and it becomes the default handler for http and https. Signed with a self-signed certificate and not notarized, so Gatekeeper blocks the first launch: right-click the app and choose Open, or run \`xattr -dr com.apple.quarantine \"/Applications/$(APP_NAME).app\"\`." \
		"$(ZIP)#$(APP_NAME) $(VERSION) (macOS)"
	@echo "Released v$(VERSION)"
