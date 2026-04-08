import Cocoa
import Carbon.HIToolbox

final class TextInjector {

    func inject(_ text: String, completion: (() -> Void)? = nil) {
        guard !text.isEmpty else { completion?(); return }

        // Type text directly via CGEvent Unicode — no clipboard needed
        DispatchQueue.global(qos: .userInitiated).async {
            self.typeUnicode(text)
            DispatchQueue.main.async { completion?() }
        }
    }

    // MARK: - CGEvent Unicode typing

    private func typeUnicode(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        let utf16 = Array(text.utf16)
        let chunkSize = 18  // safe limit for keyboardSetUnicodeString

        for i in stride(from: 0, to: utf16.count, by: chunkSize) {
            let end = min(i + chunkSize, utf16.count)
            var chunk = Array(utf16[i..<end])

            guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            else { continue }

            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)

            usleep(8000)  // 8ms between chunks for reliability
        }
    }
}
