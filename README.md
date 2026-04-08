# ClaudeVoice

A macOS menu-bar voice input app. Press a trigger key, speak, and text is typed into the focused input field.

## Features

- **Multiple ASR Engines** (switchable from menu bar):
  - **Apple (Streaming)** -- built-in, no setup needed, real-time partial results
  - **Whisper (Local)** -- via [whisper.cpp](https://github.com/ggerganov/whisper.cpp) server
  - **Qwen3-ASR (MLX)** -- via [mlx-qwen3-asr](https://github.com/moona3k/mlx-qwen3-asr), native Apple Silicon
  - **Cohere Transcribe** -- via remote vLLM server, #1 on Open ASR Leaderboard
- **Recording Modes**: Hold, Toggle (Enter to send), Auto (silence detection)
- **LLM Refinement** (optional): Clean up filler words using local [Ollama](https://ollama.com) LLM
- **Languages**: Chinese, English, Japanese, Korean, Auto
- **HUD Capsule**: Floating waveform animation with real-time transcription preview
- **Streaming**: Partial results displayed during recording (API engines)
- **Unicode Typing**: Direct CGEvent text injection (no clipboard)

## Requirements

- macOS 14.0+
- Apple Silicon (M1/M2/M3/M4)
- Accessibility permission (for key monitoring)
- Microphone permission

## Quick Start

```bash
# Build and install
make install

# Run
open /Applications/ClaudeVoice9.app
```

Grant **Accessibility** and **Microphone** permissions when prompted.

The app runs as a menu-bar icon (no Dock icon). Click the microphone icon to configure.

## ASR Engine Setup

### Apple (Streaming) -- No setup needed
Built-in macOS speech recognition. Works out of the box.

### Whisper (Local)
Requires [whisper.cpp](https://github.com/ggerganov/whisper.cpp) server:
```bash
# Install whisper.cpp and download a model, then:
./whisper-server --model ggml-large-v3.bin --port 2023 --language auto
```

### Qwen3-ASR (MLX) -- Recommended for Chinese
Best Chinese recognition on Apple Silicon:
```bash
pip install "mlx-qwen3-asr[serve]"
mlx-qwen3-asr serve --port 10800 --api-key test123 --model Qwen/Qwen3-ASR-1.7B
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
| `WhisperClient.swift` | OpenAI-compatible API client (Whisper/Qwen3/Cohere) |
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
