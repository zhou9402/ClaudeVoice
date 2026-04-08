APP_NAME    = ClaudeVoice9
BUILD_DIR   = .build
RELEASE_BIN = $(BUILD_DIR)/release/$(APP_NAME)
APP_BUNDLE  = $(BUILD_DIR)/$(APP_NAME).app

.PHONY: build run install clean setup serve serve-small stop

build:
	swift build -c release
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(RELEASE_BIN)" "$(APP_BUNDLE)/Contents/MacOS/"
	@cp Resources/Info.plist "$(APP_BUNDLE)/Contents/"
	@codesign --force --sign - "$(APP_BUNDLE)"
	@echo "✓ Built: $(APP_BUNDLE)"

run: build
	@open "$(APP_BUNDLE)"

install: build
	@cp -r "$(APP_BUNDLE)" /Applications/
	@echo "✓ Installed to /Applications/$(APP_NAME).app"

setup:
	@echo "Installing mlx-qwen3-asr..."
	pip install "mlx-qwen3-asr[serve]"
	@echo "Pre-downloading Qwen3-ASR 1.7B model..."
	python -c "from huggingface_hub import snapshot_download; snapshot_download('Qwen/Qwen3-ASR-1.7B')"
	@echo "✓ Setup complete. Run 'make serve' to start the ASR server."

serve:
	@echo "Starting Qwen3-ASR 1.7B on port 10800..."
	@mlx-qwen3-asr serve --port 10800 --api-key test123 --model Qwen/Qwen3-ASR-1.7B &
	@echo "✓ Server running on http://localhost:10800"

serve-small:
	@echo "Starting Qwen3-ASR 0.6B on port 10801..."
	@mlx-qwen3-asr serve --port 10801 --api-key test123 --model Qwen/Qwen3-ASR-0.6B &
	@echo "✓ Server running on http://localhost:10801"

stop:
	@pkill -f "mlx-qwen3-asr serve" 2>/dev/null && echo "✓ Stopped ASR server(s)" || echo "No server running"

clean:
	swift package clean
	@rm -rf "$(APP_BUNDLE)"
