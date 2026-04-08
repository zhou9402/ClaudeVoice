# ClaudeVoice

A macOS menu-bar voice input app. Press a trigger key, speak, and text is typed into the focused input field.

## Features

- **Multiple ASR Engines** (switchable from menu bar):
  - **Apple (Streaming)** -- built-in, no setup needed, real-time partial results
  - **Qwen3-ASR 1.7B (MLX)** -- best accuracy on Apple Silicon, via [mlx-qwen3-asr](https://github.com/moona3k/mlx-qwen3-asr)
  - **Qwen3-ASR 0.6B (MLX)** -- faster, lower latency variant
  - **Cohere Transcribe** -- via remote vLLM server, #1 on Open ASR Leaderboard
- **Recording Modes**: Hold, Toggle (Enter to send), Auto (silence detection)
- **LLM Refinement** (optional): Clean up filler words using local [Ollama](https://ollama.com) LLM
- **Languages**: Chinese, English, Japanese, Korean, Auto
- **HUD Capsule**: Floating waveform animation with real-time transcription preview
- **Streaming**: Partial results displayed during recording
- **Unicode Typing**: Direct CGEvent text injection (no clipboard)

## Requirements

- macOS 14.0+
- Apple Silicon (M1/M2/M3/M4)
- Accessibility permission (for key monitoring)
- Microphone permission

## Quick Start

```bash
# Install ASR model and dependencies
make setup

# Build and install the app
make install

# Start the ASR server
make serve

# Run the app
open /Applications/ClaudeVoice9.app
```

Grant **Accessibility** and **Microphone** permissions when prompted.

The app runs as a menu-bar icon (no Dock icon). Click the microphone icon to configure.

## ASR Engine Setup

### Apple (Streaming) -- No setup needed
Built-in macOS speech recognition. Works out of the box.

### Qwen3-ASR (MLX) -- Recommended
Best recognition on Apple Silicon. One-step setup:
```bash
make setup    # installs mlx-qwen3-asr + downloads 1.7B model
make serve    # starts 1.7B server on port 10800
```

To also run the faster 0.6B model:
```bash
make serve-small   # starts 0.6B server on port 10801
```

Switch between models from the menu bar.

To stop the server:
```bash
make stop
```

### Cohere Transcribe -- Best overall accuracy
Requires a GPU server with [vLLM](https://docs.vllm.ai):
```bash
# On a GPU server:
docker run -d --gpus '"device=0"' -p 8000:8000 \
  vllm/vllm-openai:latest \
  --model CohereLabs/cohere-transcribe-03-2026 --port 8000 --host 0.0.0.0
```

## LLM Refinement (Optional)

Removes filler words from transcription using a local LLM via [Ollama](https://ollama.com):
```bash
# Install Ollama, then pull a small model:
ollama pull qwen3:1.7b
```
Enable from menu bar: **LLM Refinement (Ollama)**.

## Default Trigger Key

**Right Option** key. Changeable from menu bar.

## Architecture

| File | Description |
|------|-------------|
| `AppDelegate.swift` | Central orchestrator, recording flow, mode handling |
| `AudioEngine.swift` | AVAudioEngine, RMS calculation, WAV export |
| `WhisperClient.swift` | OpenAI-compatible API client (Qwen3/Cohere) |
| `SpeechRecognizer.swift` | Apple SFSpeechRecognizer streaming wrapper |
| `LLMRefiner.swift` | Ollama LLM integration for text cleanup |
| `TextInjector.swift` | CGEvent Unicode text typing |
| `FnKeyMonitor.swift` | Global hotkey monitoring via CGEvent tap |
| `MenuBarManager.swift` | NSStatusItem menu bar UI |
| `CapsulePanel.swift` | Floating HUD window |
| `WaveformView.swift` | 5-bar waveform animation |
| `Settings.swift` | UserDefaults persistence |

## License

MIT
