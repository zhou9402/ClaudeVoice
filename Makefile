APP_NAME    = ClaudeVoice15
BUILD_DIR   = .build
RELEASE_BIN = $(BUILD_DIR)/release/$(APP_NAME)
APP_BUNDLE  = $(BUILD_DIR)/$(APP_NAME).app

.PHONY: build run install clean

build:
	swift build -c release
	@bash scripts/build_metallib.sh
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(RELEASE_BIN)" "$(APP_BUNDLE)/Contents/MacOS/"
	@cp Resources/Info.plist "$(APP_BUNDLE)/Contents/"
	@cp /tmp/metallib_build/mlx.metallib "$(APP_BUNDLE)/Contents/MacOS/"
	@codesign --force --deep --sign - --options linker-signed "$(APP_BUNDLE)"
	@echo "✓ Built: $(APP_BUNDLE)"

run: build
	@open "$(APP_BUNDLE)"

install: build
	@cp -r "$(APP_BUNDLE)" /Applications/
	@echo "✓ Installed to /Applications/$(APP_NAME).app"

clean:
	swift package clean
	@rm -rf "$(APP_BUNDLE)"
