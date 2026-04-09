import Foundation
import Qwen3ASR

final class NativeASREngine {
    private var smallModel: Qwen3ASRModel?
    private var largeModel: Qwen3ASRModel?
    private var loadingSize: ASRModelSize?

    func isReady(for engine: STTEngine) -> Bool {
        switch engine {
        case .qwen3:      return largeModel != nil
        case .qwen3Small: return smallModel != nil
        default:          return false
        }
    }

    /// Load model for the given engine (downloads weights on first use).
    func loadModel(for engine: STTEngine, progress: ((Double, String) -> Void)? = nil) async throws {
        let size: ASRModelSize = engine == .qwen3 ? .large : .small
        guard !isReady(for: engine), loadingSize != size else { return }
        loadingSize = size

        NSLog("[NativeASR] Loading %@ model...", size == .large ? "1.7B" : "0.6B")
        do {
            let model = try await Qwen3ASRModel.fromPretrained(
                modelId: size.defaultModelId,
                progressHandler: { p, s in
                    NSLog("[NativeASR] %@ (%.0f%%)", s, p * 100)
                    progress?(p, s)
                }
            )

            if size == .large {
                largeModel = model
            } else {
                smallModel = model
            }
            loadingSize = nil
            NSLog("[NativeASR] Model loaded successfully")
        } catch {
            loadingSize = nil
            NSLog("[NativeASR] Failed to load model: %@", error.localizedDescription)
            throw error
        }
    }

    /// Transcribe float samples (16kHz mono). Blocking — call from a background thread/Task.
    func transcribe(samples: [Float], engine: STTEngine, language: String?) -> String {
        let model: Qwen3ASRModel?
        switch engine {
        case .qwen3:      model = largeModel
        case .qwen3Small: model = smallModel
        default:          return ""
        }

        guard let model else {
            NSLog("[NativeASR] Model not loaded for %@", engine.displayName)
            return ""
        }
        guard !samples.isEmpty else { return "" }
        NSLog("[NativeASR] Transcribing %d samples...", samples.count)
        let result = model.transcribe(audio: samples, sampleRate: 16000, language: language)
        NSLog("[NativeASR] Result: %@", result.isEmpty ? "(empty)" : result)
        return result
    }
}
