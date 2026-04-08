import Cocoa

final class MenuBarManager: NSObject {

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    var onTriggerKeyChanged: ((TriggerKey) -> Void)?
    var onRecordingModeChanged: ((RecordingMode) -> Void)?
    var onLanguageChanged: ((WhisperLanguage) -> Void)?
    var onSTTEngineChanged: ((STTEngine) -> Void)?
    private var retryAction: (() -> Void)?
    var currentTriggerKey: TriggerKey = .rightOption
    var currentRecordingMode: RecordingMode = .hold
    var currentLanguage: WhisperLanguage = .chinese
    var currentSTTEngine: STTEngine = .qwen3

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem?.button {
            btn.image = NSImage(systemSymbolName: "mic.fill",
                                accessibilityDescription: "Voice Input")
        }
        rebuildMenu()
    }

    func setRecording(_ on: Bool) {
        statusItem?.button?.contentTintColor = on ? .systemRed : nil
    }

    // MARK: - Menu

    func rebuildMenu() {
        let m = NSMenu()

        // — Language submenu —
        let langItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for lang in WhisperLanguage.allCases {
            let item = NSMenuItem(title: lang.displayName,
                                  action: #selector(languageSelected(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = lang.rawValue
            item.state = (lang == currentLanguage) ? .on : .off
            langMenu.addItem(item)
        }
        langItem.submenu = langMenu
        m.addItem(langItem)

        m.addItem(.separator())

        // — Trigger Key submenu —
        let triggerItem = NSMenuItem(title: "Trigger Key", action: nil, keyEquivalent: "")
        let triggerMenu = NSMenu()
        for key in TriggerKey.allCases {
            let item = NSMenuItem(title: key.displayName,
                                  action: #selector(triggerKeySelected(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = key.rawValue
            item.state = (key == currentTriggerKey) ? .on : .off
            triggerMenu.addItem(item)
        }
        triggerItem.submenu = triggerMenu
        m.addItem(triggerItem)

        // — Recording Mode submenu —
        let modeItem = NSMenuItem(title: "Recording Mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in RecordingMode.allCases {
            let item = NSMenuItem(title: mode.displayName,
                                  action: #selector(modeSelected(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = (mode == currentRecordingMode) ? .on : .off
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        m.addItem(modeItem)

        // — STT Engine submenu —
        let sttItem = NSMenuItem(title: "STT Engine", action: nil, keyEquivalent: "")
        let sttMenu = NSMenu()
        for engine in STTEngine.allCases {
            let item = NSMenuItem(title: engine.displayName,
                                  action: #selector(sttEngineSelected(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = engine.rawValue
            item.state = (engine == currentSTTEngine) ? .on : .off
            sttMenu.addItem(item)
        }
        sttItem.submenu = sttMenu
        m.addItem(sttItem)

        // — LLM Refinement toggle —
        m.addItem(.separator())
        let llmItem = NSMenuItem(title: "LLM Refinement (Ollama)",
                                  action: #selector(llmToggled(_:)),
                                  keyEquivalent: "")
        llmItem.target = self
        llmItem.state = Settings.shared.llmRefinement ? .on : .off
        m.addItem(llmItem)

        // — Retry Accessibility (shown only when needed) —
        if retryAction != nil {
            m.addItem(.separator())
            let retry = NSMenuItem(title: "Retry Accessibility Permission",
                                   action: #selector(retryTapped(_:)),
                                   keyEquivalent: "")
            retry.target = self
            m.addItem(retry)
        }

        m.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Claude Voice",
                              action: #selector(quitApp(_:)),
                              keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)

        menu = m
        statusItem?.menu = m
    }

    // MARK: - Actions

    @objc private func languageSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = WhisperLanguage(rawValue: raw) else { return }
        currentLanguage = lang
        onLanguageChanged?(lang)
        rebuildMenu()
    }

    @objc private func triggerKeySelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let key = TriggerKey(rawValue: raw) else { return }
        currentTriggerKey = key
        onTriggerKeyChanged?(key)
        rebuildMenu()
    }

    @objc private func modeSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = RecordingMode(rawValue: raw) else { return }
        currentRecordingMode = mode
        onRecordingModeChanged?(mode)
        rebuildMenu()
    }

    @objc private func sttEngineSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let engine = STTEngine(rawValue: raw) else { return }
        currentSTTEngine = engine
        onSTTEngineChanged?(engine)
        rebuildMenu()
    }

    @objc private func llmToggled(_ sender: NSMenuItem) {
        Settings.shared.llmRefinement.toggle()
        rebuildMenu()
    }

    @objc private func retryTapped(_ sender: NSMenuItem) {
        retryAction?()
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    func addRetryItem(action: @escaping () -> Void) {
        retryAction = action
        rebuildMenu()
    }

    func removeRetryItem() {
        retryAction = nil
        rebuildMenu()
    }
}
