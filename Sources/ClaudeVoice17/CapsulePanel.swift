import Cocoa
import QuartzCore

final class CapsulePanel: NSPanel {

    // Layout constants
    private let capsuleH: CGFloat    = 56
    private let cornerR: CGFloat     = 28
    private let leftPad: CGFloat     = 16
    private let rightPad: CGFloat    = 20
    private let gap: CGFloat         = 12
    private let waveW: CGFloat       = 44
    private let waveH: CGFloat       = 32
    private let minLabelW: CGFloat   = 160
    private let maxLabelW: CGFloat   = 560

    private var minTotalW: CGFloat { leftPad + waveW + gap + minLabelW + rightPad }
    private var maxTotalW: CGFloat { leftPad + waveW + gap + maxLabelW + rightPad }

    // Subviews
    private var effectView: NSVisualEffectView!
    private var waveformView: WaveformView!
    private var textLabel: NSTextField!
    private var containerView: NSView!

    // MARK: - Init

    init() {
        let w = 16 + 44 + 12 + 160 + 20  // minTotalW = 252
        let frame = NSRect(x: 0, y: 0, width: CGFloat(w), height: 56)
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        buildViews()
    }

    // MARK: - Public

    func show() {
        positionOnScreen()
        textLabel.stringValue = ""

        // Prepare for spring entry
        alphaValue = 0
        containerView.layer?.transform = CATransform3DMakeScale(0.85, 0.85, 1)
        orderFront(nil)

        // Fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }

        // Spring scale
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.85
        spring.toValue = 1.0
        spring.damping = 14
        spring.stiffness = 280
        spring.mass = 1.0
        spring.initialVelocity = 0
        spring.duration = 0.35
        containerView.layer?.transform = CATransform3DIdentity
        containerView.layer?.add(spring, forKey: "entrySpring")
    }

    func dismiss(completion: (() -> Void)? = nil) {
        waveformView.stopAnimating()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.containerView.layer?.transform = CATransform3DIdentity
            self?.alphaValue = 1
            completion?()
        })

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 0.88
        scale.duration = 0.22
        scale.timingFunction = CAMediaTimingFunction(name: .easeIn)
        scale.isRemovedOnCompletion = false
        scale.fillMode = .forwards
        containerView.layer?.add(scale, forKey: "exitScale")
    }

    func updateRMS(_ level: Float) {
        waveformView.updateRMS(level)
    }

    func updateText(_ text: String) {
        textLabel.textColor = .white
        textLabel.stringValue = text
        adjustWidth(for: text)
    }

    func showRefining() {
        textLabel.stringValue = "Refining..."
        textLabel.textColor = NSColor.white.withAlphaComponent(0.55)
    }

    func showHint(_ hint: String) {
        textLabel.stringValue = hint
        textLabel.textColor = NSColor.white.withAlphaComponent(0.4)
    }

    // MARK: - Build views

    private func buildViews() {
        containerView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        containerView.wantsLayer = true
        contentView = containerView

        // Background blur
        effectView = NSVisualEffectView(frame: containerView.bounds)
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = cornerR
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]
        containerView.addSubview(effectView)

        // Waveform
        let wFrame = NSRect(x: leftPad, y: (capsuleH - waveH) / 2, width: waveW, height: waveH)
        waveformView = WaveformView(frame: wFrame)
        containerView.addSubview(waveformView)

        // Label
        let labelX = leftPad + waveW + gap
        textLabel = NSTextField(labelWithString: "")
        textLabel.font = .systemFont(ofSize: 15, weight: .medium)
        textLabel.textColor = .white
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 1
        textLabel.cell?.truncatesLastVisibleLine = true
        let labelH = textLabel.intrinsicContentSize.height
        textLabel.frame = NSRect(x: labelX, y: (capsuleH - labelH) / 2,
                                 width: minLabelW, height: labelH)
        containerView.addSubview(textLabel)
    }

    // MARK: - Elastic width

    private func adjustWidth(for text: String) {
        guard let font = textLabel.font else { return }
        let textW = (text as NSString)
            .size(withAttributes: [.font: font]).width + 12
        let clampedLabelW = min(max(textW, minLabelW), maxLabelW)
        let totalW = leftPad + waveW + gap + clampedLabelW + rightPad

        guard abs(totalW - frame.width) > 2 else { return }

        var newFrame = frame
        let cx = newFrame.midX
        newFrame.size.width = totalW
        newFrame.origin.x = cx - totalW / 2

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(newFrame, display: true)
        }

        // Resize subviews (effectView auto-resizes; update label width)
        textLabel.frame.size.width = clampedLabelW
    }

    // MARK: - Positioning

    private func positionOnScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let vis = screen.visibleFrame
        let x = vis.midX - frame.width / 2
        let y = vis.origin.y + 80
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
