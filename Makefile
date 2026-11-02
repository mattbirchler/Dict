PROJECT = Dict-app.xcodeproj
SCHEME = Dict-app
DERIVED = build
XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -destination 'platform=macOS'

.PHONY: build test run install notarize publish clean

# Build output is filtered to errors, app-source warnings, and the result line,
# but the exit status is xcodebuild's so failures stop whatever invoked make.
build:
	@mkdir -p $(DERIVED)
	@$(XCODEBUILD) -configuration Debug build > $(DERIVED)/last-build.log 2>&1; status=$$?; \
	grep -E "error:|warning:.*Dict-app/Dict-app/|BUILD (SUCCEEDED|FAILED)" $(DERIVED)/last-build.log | sort -u; \
	exit $$status

# Unit tests. The Parakeet end-to-end test needs the 500 MB model, so it
# only runs with: make test E2E=1
test:
	@mkdir -p $(DERIVED)
	@$(XCODEBUILD) $(if $(E2E),,-skip-testing:Dict-appTests/ParakeetEndToEndTests) test > $(DERIVED)/last-test.log 2>&1; status=$$?; \
	grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)" $(DERIVED)/last-test.log | sort -u; \
	exit $$status

run: build
	@pkill -x Dict || true
	open $(DERIVED)/Build/Products/Debug/Dict.app

# Release build copied into /Applications.
install:
	@mkdir -p $(DERIVED)
	@$(XCODEBUILD) -configuration Release build > $(DERIVED)/last-release.log 2>&1; status=$$?; \
	grep -E "error:|BUILD (SUCCEEDED|FAILED)" $(DERIVED)/last-release.log | sort -u; \
	exit $$status
	@pkill -x Dict || true
	@rm -rf /Applications/Dict.app
	cp -R $(DERIVED)/Build/Products/Release/Dict.app /Applications/Dict.app
	@echo "Installed /Applications/Dict.app"

# A Release build signed with Developer ID and notarized by Apple, zipped
# in build/notarized/ so it opens on any Mac. Needs fastlane/.env.
notarize:
	@scripts/notarize.sh

# Ship a new version to everyone through Sparkle. Needs release notes:
#   make publish NOTES=notes.md [VERSION=1.1]
publish:
	@NOTES="$(NOTES)" VERSION="$(VERSION)" scripts/publish.sh

clean:
	rm -rf $(DERIVED)
