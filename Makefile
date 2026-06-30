# hollowlullaby — common dev commands.
# iOS simulator name can be overridden: make ios-run SIM="iPhone 16"
# Physical device UDID can be overridden: make device-run DEVICE=<udid>
SIM ?= iPhone 16
DEVICE ?= 8B363280-D4AA-58BE-9681-361C8A3718AC
BUNDLE_ID := com.ngmob.hollowlullaby
DEVICE_APP := build/DerivedData/Build/Products/Debug-iphoneos/hollowlullaby.app

.PHONY: run build check fmt clippy ios-lib ios-project ios-build ios-run \
        device-build device-run clean

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
device-build: ios-project   ## Build & sign the app for a physical device
	xcodebuild -project hollowlullaby.xcodeproj -scheme hollowlullaby \
		-configuration Debug -sdk iphoneos \
		-destination 'generic/platform=iOS' \
		-derivedDataPath build/DerivedData \
		-allowProvisioningUpdates build

device-run: device-build    ## Build, install, and launch on the connected device
	xcrun devicectl device install app --device "$(DEVICE)" "$(DEVICE_APP)"
	xcrun devicectl device process launch --device "$(DEVICE)" $(BUNDLE_ID)

clean:
	cargo clean
	rm -rf build hollowlullaby.xcodeproj
