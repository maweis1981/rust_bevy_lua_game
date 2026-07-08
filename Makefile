# hollowlullaby — common dev commands.
# iOS simulator name can be overridden: make ios-run SIM="iPhone 16"
# Physical device UDID can be overridden: make device-run DEVICE=<udid>
SIM ?= iPhone 16
DEVICE ?= 8B363280-D4AA-58BE-9681-361C8A3718AC
BUNDLE_ID := com.ngmob.hollow
# Build configuration for device runs. Use CONFIG=Release for a smooth,
# optimized build (Debug runs Bevy/wgpu with debug assertions and is much slower).
CONFIG ?= Debug
DEVICE_APP := build/DerivedData/Build/Products/$(CONFIG)-iphoneos/hollowlullaby.app

.PHONY: run build check fmt clippy test test-lua web web-games web-serve ios-lib \
        ios-project ios-build ios-run device-build device-run ios-archive \
        ios-export ios-ipa clean new-game

# Output locations for the App Store archive + exported IPA (TestFlight).
ARCHIVE := build/hollowlullaby.xcarchive
IPA_DIR := build/ipa

# Lua interpreter for the gameplay tests (override: make test LUA=lua)
LUA ?= lua5.4

# --- Desktop ---------------------------------------------------------------
run:            ## Run the game on macOS (hot-reloads assets/scripts/*.lua)
	cargo run

build:
	cargo build

check:
	cargo check

fmt:
	cargo fmt

clippy:
	cargo clippy --all-targets

test: test-lua      ## Run Rust unit tests + the Lua gameplay invariant suite
	cargo test

# Headless gameplay tests: drive assets/scripts/main.lua under a mocked host API
# and assert the "game feel" invariants (no teleport/tunnel, speed cap, serve
# pause, effects fire). Skipped with a note if no Lua interpreter is installed.
test-lua:
	@command -v $(LUA) >/dev/null 2>&1 \
		&& $(LUA) tools/test_pong.lua \
		&& $(LUA) tools/test_m0_packs.lua \
		|| echo "skip: $(LUA) not found (brew install lua) — gameplay tests not run"

# --- Web (WebAssembly) -----------------------------------------------------
# Build a static browser bundle into build/web/ (index.html + .js + .wasm +
# assets/). The web build uses a pure-Rust Lua VM (ottavino) instead of mlua;
# gameplay/scripts are identical. See docs/web-poc/.
# One-time setup: rustup target add wasm32-unknown-unknown
#                 cargo install wasm-bindgen-cli   (match the wasm-bindgen crate)
#                 (optional) install binaryen for wasm-opt
web:            ## Build the static web bundle into build/web/
	bash web/build.sh

web-games:      ## Export one standalone web bundle per game (run 'make web' first)
	bash tools/export_web_games.sh

web-serve: web  ## Build the web bundle and serve it at http://localhost:8080
	@echo "serving build/web at http://localhost:8080 (Ctrl-C to stop)"
	@cd build/web && python3 -m http.server 8080

# --- iOS -------------------------------------------------------------------
ios-lib:        ## Cross-compile the Rust static lib for the simulator
	PLATFORM_NAME=iphonesimulator CONFIGURATION=Debug \
		bash ios/build_rust.sh build/ios

ios-project:    ## (Re)generate hollowlullaby.xcodeproj from project.yml
	xcodegen generate

ios-build: ios-project   ## Build the iOS app for the simulator
	xcodebuild -project hollowlullaby.xcodeproj -scheme hollowlullaby \
		-configuration Debug -sdk iphonesimulator \
		-destination 'generic/platform=iOS Simulator' \
		-derivedDataPath build/DerivedData build

ios-run: ios-build       ## Build, install, and launch on the named simulator
	xcrun simctl boot "$(SIM)" 2>/dev/null || true
	open -a Simulator
	xcrun simctl install "$(SIM)" \
		"build/DerivedData/Build/Products/Debug-iphonesimulator/hollowlullaby.app"
	xcrun simctl launch --console "$(SIM)" $(BUNDLE_ID)

# --- iOS physical device ---------------------------------------------------
device-build: ios-project   ## Build & sign for a device (CONFIG=Debug|Release)
	xcodebuild -project hollowlullaby.xcodeproj -scheme hollowlullaby \
		-configuration $(CONFIG) -sdk iphoneos \
		-destination 'generic/platform=iOS' \
		-derivedDataPath build/DerivedData \
		-allowProvisioningUpdates build

device-run: device-build    ## Build, install, and launch on the connected device
	xcrun devicectl device install app --device "$(DEVICE)" "$(DEVICE_APP)"
	xcrun devicectl device process launch --device "$(DEVICE)" $(BUNDLE_ID)

# --- TestFlight / App Store ------------------------------------------------
# Archive a Release build for distribution (Apple Distribution signing is created
# automatically via -allowProvisioningUpdates; needs a paid Developer account).
ios-archive: ios-project   ## Archive a Release build for the App Store
	xcodebuild -project hollowlullaby.xcodeproj -scheme hollowlullaby \
		-configuration Release -sdk iphoneos \
		-destination 'generic/platform=iOS' \
		-archivePath "$(ARCHIVE)" \
		-allowProvisioningUpdates archive

# Export a signed .ipa from the archive using ios/ExportOptions.plist.
ios-export:                ## Export a signed .ipa from the archive
	xcodebuild -exportArchive -archivePath "$(ARCHIVE)" \
		-exportOptionsPlist ios/ExportOptions.plist \
		-exportPath "$(IPA_DIR)" \
		-allowProvisioningUpdates
	@echo "IPA ready: $(IPA_DIR)/hollowlullaby.ipa"
	@echo "Upload it with Transporter (App Store) or Xcode Organizer."

# One shot: archive then export the IPA for TestFlight.
ios-ipa: ios-archive ios-export   ## Archive + export the TestFlight .ipa

clean:
	cargo clean
	rm -rf build hollowlullaby.xcodeproj

new-game:  ## scaffold a new game pack: make new-game NAME=asteroids
	@sh tools/new_game.sh "$(NAME)"
