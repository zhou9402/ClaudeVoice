import Foundation

enum STTEngine: String, CaseIterable {
    case whisper = "whisper"
    case qwen3 = "qwen3"
    case cohere = "cohere"
    case apple = "apple"

    var displayName: String {
        switch self {
        case .whisper: return "Whisper (Local)"
        case .qwen3:   return "Qwen3-ASR (MLX)"
        case .cohere:  return "Cohere Transcribe"
        case .apple:   return "Apple (Streaming)"
        }
    }

    var defaultURL: String {
        switch self {
        case .whisper: return "http://localhost:2023"
        case .qwen3:   return "http://localhost:10800"
        case .cohere:  return "http://10.6.131.5:8000"
        case .apple:   return ""
        }
    }

    var modelName: String {
        switch self {
        case .whisper: return "whisper-1"
        case .qwen3:   return "Qwen/Qwen3-ASR-1.7B"
        case .cohere:  return "CohereLabs/cohere-transcribe-03-2026"
        case .apple:   return ""
        }
    }

    var defaultAPIKey: String {
        switch self {
        case .qwen3:  return "test123"
        default:      return ""
        }
    }

    /// True for engines that use OpenAI-compatible /v1/audio/transcriptions API
    var isLocalAPI: Bool {
        self != .apple
    }
}

enum WhisperLanguage: String, CaseIterable {
    case chinese = "zh"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case auto = "auto"

    var displayName: String {
        switch self {
        case .chinese:  return "中文"
        case .english:  return "English"
        case .japanese: return "日本語"
        case .korean:   return "한국어"
        case .auto:     return "Auto"
        }
    }

    /// nil means don't send language param (let server decide)
    var apiValue: String? {
        self == .auto ? nil : rawValue
    }

    /// Locale for Apple SFSpeechRecognizer
    var locale: Locale {
        switch self {
        case .chinese:  return Locale(identifier: "zh-CN")
        case .english:  return Locale(identifier: "en-US")
        case .japanese: return Locale(identifier: "ja-JP")
        case .korean:   return Locale(identifier: "ko-KR")
        case .auto:     return Locale(identifier: "zh-CN")
        }
    }
}

enum RecordingMode: String, CaseIterable {
    case hold = "hold"
    case toggle = "toggle"
    case auto = "auto"

    var displayName: String {
        switch self {
        case .hold:   return "Hold to Record"
        case .toggle: return "Toggle (Enter to Send)"
        case .auto:   return "Auto (Silence Stops)"
        }
    }
}

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let sttEngine = "sttEngine"
        static let recordingMode = "recordingMode"
        static let whisperLanguage = "whisperLanguage"
        static let whisperURL = "whisperURL"
    }

    var sttEngine: STTEngine {
        get {
            if let raw = defaults.string(forKey: Keys.sttEngine),
               let engine = STTEngine(rawValue: raw) {
                return engine
            }
            return .whisper
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.sttEngine) }
    }

    var recordingMode: RecordingMode {
        get {
            if let raw = defaults.string(forKey: Keys.recordingMode),
               let mode = RecordingMode(rawValue: raw) {
                return mode
            }
            return .hold
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.recordingMode) }
    }

    var whisperLanguage: WhisperLanguage {
        get {
            if let raw = defaults.string(forKey: Keys.whisperLanguage),
               let lang = WhisperLanguage(rawValue: raw) {
                return lang
            }
            return .english
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.whisperLanguage) }
    }

    var whisperURL: String {
        get { defaults.string(forKey: Keys.whisperURL) ?? "http://localhost:2023" }
        set { defaults.set(newValue, forKey: Keys.whisperURL) }
    }

    var llmRefinement: Bool {
        get { defaults.bool(forKey: "llmRefinement") }
        set { defaults.set(newValue, forKey: "llmRefinement") }
    }

    func url(for engine: STTEngine) -> String {
        let key = "engineURL_\(engine.rawValue)"
        return defaults.string(forKey: key) ?? engine.defaultURL
    }

    func apiKey(for engine: STTEngine) -> String {
        let key = "engineAPIKey_\(engine.rawValue)"
        return defaults.string(forKey: key) ?? engine.defaultAPIKey
    }
}
