import Cocoa
import AVFoundation
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let menuBar = MenuBarManager()
    private let fnMonitor = FnKeyMonitor()
    private let audioEngine = AudioEngine()
    private let speechRecognizer = SpeechRecognizer()
    private let whisperClient = WhisperClient()
    private let textInjector = TextInjector()
    private let llmRefiner = LLMRefiner()

    private var capsule: CapsulePanel?
    private var isRecording = false
    private var isProcessing = false
    private var waitingForFinal = false
    private var currentText = ""

    // Auto-mode silence detection (smoothed RMS)
    private var recordingStartTime: Date?
    private var silenceStart: Date?
    private var smoothedRMS: Float = 0
    private let rmsSmoothing: Float = 0.3
    private let silenceThreshold: Float = 0.05
    private let silenceDuration: TimeInterval = 1.2
    private let minRecordingTime: TimeInterval = 0.8

    // Streaming partial results (growing window)
    private var streamingTimer: Timer?
    private var streamingTask: Task<Void, Never>?
    private var isStreamingRequestPending = false
    private var waitingForStreamingResult = false
    private var streamingGeneration = 0
    private let streamingInterval: TimeInterval = 2.0

    private var recordingMode: RecordingMode { Settings.shared.recordingMode }
    private var sttEngine: STTEngine { Settings.shared.sttEngine }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        SFSpeechRecognizer.requestAuthorization { _ in }

        menuBar.setup()
        menuBar.currentTriggerKey = fnMonitor.triggerKey
        menuBar.currentRecordingMode = Settings.shared.recordingMode
        menuBar.currentLanguage = Settings.shared.whisperLanguage
        menuBar.currentSTTEngine = Settings.shared.sttEngine
        menuBar.onLanguageChanged = { lang in
            Settings.shared.whisperLanguage = lang
        }
        menuBar.onTriggerKeyChanged = { [weak self] key in
            self?.fnMonitor.triggerKey = key
        }
        menuBar.onRecordingModeChanged = { [weak self] mode in
            Settings.shared.recordingMode = mode
            if self?.isRecording == true { self?.cancelRecording() }
        }
        menuBar.onSTTEngineChanged = { [weak self] engine in
            Settings.shared.sttEngine = engine
            if self?.isRecording == true { self?.cancelRecording() }
        }

        fnMonitor.onFnDown = { [weak self] in self?.handleTriggerDown() }
        fnMonitor.onFnUp   = { [weak self] in self?.handleTriggerUp() }
        fnMonitor.onEnterPressed = { [weak self] in self?.handleEnterPressed() }

        attemptStartMonitor()
    }

    // MARK: - Mode-aware trigger handling

    private func handleTriggerDown() {
        switch recordingMode {
        case .hold:
            startRecording()
        case .toggle, .auto:
            if !isRecording { startRecording() }
        }
    }

    private func handleTriggerUp() {
        switch recordingMode {
        case .hold:
            stopRecording()
        case .toggle, .auto:
            break
        }
    }

    private func handleEnterPressed() {
        guard isRecording else { return }
        switch recordingMode {
        case .toggle, .auto:
            stopRecording()
        case .hold:
            break
        }
    }

    // MARK: - Recording flow

    private func startRecording() {
        guard !isRecording, !isProcessing else { return }
        isRecording = true
        currentText = ""
        waitingForFinal = false
        waitingForStreamingResult = false
        streamingGeneration += 1
        recordingStartTime = Date()
        silenceStart = nil

        fnMonitor.isRecordingActive = (recordingMode != .hold)
        menuBar.setRecording(true)

        capsule = CapsulePanel()
        if recordingMode == .toggle {
            capsule?.showHint("Press Enter \u{23CE} to send")
        }
        capsule?.show()

        let useLocalAPI = sttEngine.isLocalAPI

        if !useLocalAPI {
            // Apple SFSpeechRecognizer: streaming partial results
            speechRecognizer.onPartialResult = { [weak self] text in
                self?.currentText = text
                self?.capsule?.updateText(text)
            }
            speechRecognizer.onFinalResult = { [weak self] text in
                guard let self else { return }
                self.currentText = text
                self.capsule?.updateText(text)
                if self.waitingForFinal {
                    self.waitingForFinal = false
                    self.processResult(text)
                }
            }
            speechRecognizer.onError = { error in
                print("[SpeechRecognizer] \(error.localizedDescription)")
            }
            speechRecognizer.start(locale: Settings.shared.whisperLanguage.locale)
        }

        audioEngine.onRMSLevel = { [weak self] rms in
            self?.capsule?.updateRMS(rms)
            self?.checkSilence(rms: rms)
        }

        if !useLocalAPI {
            audioEngine.onAudioBuffer = { [weak self] buffer in
                self?.speechRecognizer.appendBuffer(buffer)
            }
        } else {
            audioEngine.onAudioBuffer = nil
        }

        do {
            try audioEngine.start(accumulate: useLocalAPI)
        } catch {
            print("[AudioEngine] \(error.localizedDescription)")
            cancelRecording()
            return
        }

        // Start streaming partial results for API engines
        if useLocalAPI {
            startStreamingTimer()
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        fnMonitor.isRecordingActive = false
        silenceStart = nil
        stopStreamingTimer()
        menuBar.setRecording(false)
        audioEngine.stop()

        if !sttEngine.isLocalAPI {
            finishAppleRecording()
            return
        }

        if recordingMode == .auto {
            // Auto mode: silence-onset snapshot has all speech — wait or use it
            if isStreamingRequestPending {
                waitingForStreamingResult = true
            } else if !currentText.isEmpty {
                processResult(currentText)
            } else {
                sendFinalTranscription()
            }
        } else {
            // Hold/toggle: cancel streaming, send one final transcription
            streamingGeneration += 1
            streamingTask?.cancel()
            streamingTask = nil
            isStreamingRequestPending = false
            sendFinalTranscription()
        }
    }

    private func finishAppleRecording() {
        waitingForFinal = true
        speechRecognizer.stopListening()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.waitingForFinal else { return }
            self.waitingForFinal = false
            self.processResult(self.currentText)
        }
    }

    /// Fallback: transcribe all accumulated audio (used when no streaming result exists).
    private func sendFinalTranscription() {
        guard let wavData = audioEngine.snapshotWAV() else {
            capsule?.dismiss { [weak self] in self?.isProcessing = false }
            return
        }

        isProcessing = true
        let engine = sttEngine
        let lang = Settings.shared.whisperLanguage.apiValue

        Task {
            let text: String
            do {
                text = try await whisperClient.transcribe(wavData: wavData, engine: engine, language: lang)
            } catch {
                print("[\(engine.displayName)] \(error.localizedDescription)")
                await MainActor.run {
                    self.capsule?.updateText("Error")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.capsule?.dismiss { self.isProcessing = false }
                    }
                }
                return
            }

            await MainActor.run {
                self.processResult(text)
            }
        }
    }

    private func cancelRecording() {
        isRecording = false
        waitingForFinal = false
        waitingForStreamingResult = false
        fnMonitor.isRecordingActive = false
        silenceStart = nil
        stopStreamingTimer()
        streamingTask?.cancel()
        streamingTask = nil
        isStreamingRequestPending = false
        menuBar.setRecording(false)
        audioEngine.stop()
        speechRecognizer.cleanup()
        capsule?.dismiss()
    }

    // MARK: - Streaming partial results

    private func startStreamingTimer() {
        streamingTimer = Timer.scheduledTimer(withTimeInterval: streamingInterval, repeats: true) { [weak self] _ in
            self?.sendStreamingSnapshot()
        }
    }

    private func stopStreamingTimer() {
        streamingTimer?.invalidate()
        streamingTimer = nil
    }

    private func sendStreamingSnapshot() {
        guard sttEngine.isLocalAPI, !isStreamingRequestPending else { return }
        guard let wavData = audioEngine.snapshotWAV() else { return }

        isStreamingRequestPending = true
        let engine = sttEngine
        let lang = Settings.shared.whisperLanguage.apiValue
        let gen = streamingGeneration

        streamingTask = Task {
            do {
                let text = try await whisperClient.transcribe(wavData: wavData, engine: engine, language: lang)
                await MainActor.run {
                    guard self.streamingGeneration == gen else { return }
                    if !text.isEmpty {
                        self.currentText = text
                        self.capsule?.updateText(text)
                    }
                    self.isStreamingRequestPending = false
                    if self.waitingForStreamingResult {
                        self.waitingForStreamingResult = false
                        self.processResult(self.currentText)
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.streamingGeneration == gen else { return }
                    self.isStreamingRequestPending = false
                    if self.waitingForStreamingResult {
                        self.waitingForStreamingResult = false
                        if !self.currentText.isEmpty {
                            self.processResult(self.currentText)
                        } else {
                            self.sendFinalTranscription()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Auto-mode silence detection

    private func checkSilence(rms: Float) {
        guard recordingMode == .auto, isRecording else {
            silenceStart = nil
            smoothedRMS = 0
            return
        }

        if let start = recordingStartTime, Date().timeIntervalSince(start) < minRecordingTime {
            smoothedRMS = rms
            return
        }

        // Exponential moving average — absorbs brief noise spikes
        smoothedRMS = rmsSmoothing * smoothedRMS + (1 - rmsSmoothing) * rms

        if smoothedRMS < silenceThreshold {
            if silenceStart == nil {
                silenceStart = Date()
                // Silence just started — invalidate old streaming and send a fresh snapshot
                // covering ALL speech. By the time 1.2s silence passes, result should be ready.
                if sttEngine.isLocalAPI {
                    streamingGeneration += 1
                    streamingTask?.cancel()
                    streamingTask = nil
                    isStreamingRequestPending = false
                    sendStreamingSnapshot()
                }
            }
            if let start = silenceStart, Date().timeIntervalSince(start) >= silenceDuration {
                stopRecording()
            }
        } else {
            silenceStart = nil
        }
    }

    // MARK: - Result processing

    private func processResult(_ text: String) {
        isProcessing = true
        speechRecognizer.cleanup()

        guard !text.isEmpty else {
            capsule?.dismiss { [weak self] in self?.isProcessing = false }
            return
        }

        capsule?.updateText(text)

        guard Settings.shared.llmRefinement else {
            injectAndDismiss(text)
            return
        }

        // Refine with local LLM
        capsule?.showHint("Refining...")
        Task {
            let refined = await llmRefiner.refine(text)
            await MainActor.run {
                self.injectAndDismiss(refined.isEmpty ? text : refined)
            }
        }
    }

    private func injectAndDismiss(_ text: String) {
        capsule?.updateText(text)
        capsule?.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.textInjector.inject(text) {
                self.isProcessing = false
            }
        }
    }

    // MARK: - Permissions

    private func attemptStartMonitor() {
        if fnMonitor.start() {
            print("[ClaudeVoice] Trigger: \(fnMonitor.triggerKey.displayName) | Mode: \(recordingMode.displayName) | STT: \(sttEngine.displayName)")
            menuBar.removeRetryItem()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            Claude Voice needs Accessibility permission to monitor the trigger key.\
            \n\nGrant it in:\nSystem Settings \u{2192} Privacy & Security \u{2192} Accessibility\
            \n\nAfter granting, click "Retry" (no relaunch needed).
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Quit")

        let resp = alert.runModal()
        switch resp {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            menuBar.addRetryItem { [weak self] in self?.attemptStartMonitor() }
        case .alertSecondButtonReturn:
            attemptStartMonitor()
        default:
            NSApp.terminate(nil)
        }
    }
}
