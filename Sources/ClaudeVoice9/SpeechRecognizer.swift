import Speech

final class SpeechRecognizer {
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    func start(locale: Locale) {
        recognizer = SFSpeechRecognizer(locale: locale)
        guard recognizer?.isAvailable == true else {
            onError?(NSError(domain: "SpeechRecognizer", code: -1,
                             userInfo: [NSLocalizedDescriptionKey:
                                "Speech recognizer not available for \(locale.identifier)"]))
            return
        }

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        request?.taskHint = .dictation

        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self?.onFinalResult?(text)
                    } else {
                        self?.onPartialResult?(text)
                    }
                }
                if let error {
                    let ns = error as NSError
                    if ns.domain == "kAFAssistantErrorDomain" && (ns.code == 216 || ns.code == 209) {
                        return
                    }
                    self?.onError?(error)
                }
            }
        }
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func stopListening() {
        request?.endAudio()
    }

    func cleanup() {
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
    }
}
