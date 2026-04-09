import Cocoa

enum TriggerKey: String, CaseIterable {
    case rightOption = "rightOption"
    case rightCommand = "rightCommand"
    case leftControl = "leftControl"
    case fn = "fn"

    var displayName: String {
        switch self {
        case .rightOption:  return "Right Option (⌥)"
        case .rightCommand: return "Right Command (⌘)"
        case .leftControl:  return "Left Control (⌃)"
        case .fn:           return "Fn (Globe 🌐)"
        }
    }

    /// Virtual keycode for the trigger key
    var keyCode: Int64 {
        switch self {
        case .rightOption:  return 0x3D  // 61
        case .rightCommand: return 0x36  // 54
        case .leftControl:  return 0x3B  // 59
        case .fn:           return 0x3F  // 63
        }
    }

    /// The modifier flag set when this key is held
    var flag: CGEventFlags {
        switch self {
        case .rightOption:  return .maskAlternate
        case .rightCommand: return .maskCommand
        case .leftControl:  return .maskControl
        case .fn:           return .maskSecondaryFn
        }
    }
}

final class FnKeyMonitor {
    var onFnDown: (() -> Void)?
    var onFnUp: (() -> Void)?
    var onEnterPressed: (() -> Void)?

    /// Set to true while recording in toggle/auto mode so Enter key is intercepted
    var isRecordingActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDown = false
    private var globalMonitor: Any?

    var triggerKey: TriggerKey = {
        if let raw = UserDefaults.standard.string(forKey: "triggerKey"),
           let key = TriggerKey(rawValue: raw) {
            return key
        }
        return .rightOption
    }() {
        didSet {
            UserDefaults.standard.set(triggerKey.rawValue, forKey: "triggerKey")
            isDown = false
        }
    }

    func start() -> Bool {
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: triggerEventTapCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Fallback NSEvent monitor for Fn/Globe key on Apple Silicon
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSFlagsChanged(event)
        }

        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }

    // MARK: - CGEvent tap

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let tk = triggerKey

        if type == .flagsChanged && keyCode == tk.keyCode {
            let hasFlag = event.flags.contains(tk.flag)
            if hasFlag && !isDown {
                isDown = true
                DispatchQueue.main.async { [weak self] in self?.onFnDown?() }
                if tk == .fn { return nil } // suppress Fn only
            } else if !hasFlag && isDown {
                isDown = false
                DispatchQueue.main.async { [weak self] in self?.onFnUp?() }
                if tk == .fn { return nil }
            }
        }

        // Suppress standalone Fn key events
        if tk == .fn && (type == .keyDown || type == .keyUp) && keyCode == 0x3F {
            return nil
        }

        // Intercept Enter key (0x24 = 36) during active recording in toggle/auto mode
        if type == .keyDown && keyCode == 0x24 && isRecordingActive {
            DispatchQueue.main.async { [weak self] in self?.onEnterPressed?() }
            return nil // suppress so Enter doesn't go to the app
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - NSEvent fallback (catches Globe key on Apple Silicon)

    private func handleNSFlagsChanged(_ event: NSEvent) {
        guard triggerKey == .fn else { return } // only needed for Fn/Globe
        let fnNow = event.modifierFlags.contains(.function)
        if fnNow && !isDown {
            isDown = true
            onFnDown?()
        } else if !fnNow && isDown {
            isDown = false
            onFnUp?()
        }
    }
}

private func triggerEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    return monitor.handleEvent(type: type, event: event)
}
