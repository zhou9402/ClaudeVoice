import Cocoa
import QuartzCore

final class WaveformView: NSView {

    // Layout
    private let barCount = 5
    private let barWidth: CGFloat = 4
    private let barGap: CGFloat = 4
    private let barRadius: CGFloat = 2
    private let minBarH: CGFloat = 5
    private let maxBarH: CGFloat = 28

    // Envelope
    private let weights: [Float] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private let attackCoeff: Float  = 0.4
    private let releaseCoeff: Float = 0.15

    private var smoothed: [Float] = [0, 0, 0, 0, 0]
    private var targetRMS: Float = 0
    private var barLayers: [CALayer] = []
    private var timer: Timer?

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true

        for _ in 0..<barCount {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.88).cgColor
            bar.cornerRadius = barRadius
            layer?.addSublayer(bar)
            barLayers.append(bar)
        }

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - API

    func updateRMS(_ rms: Float) {
        targetRMS = rms
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        layoutBars()
    }

    // MARK: - Tick

    private func tick() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let totalW = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
        let startX = (bounds.width - totalW) / 2

        for i in 0..<barCount {
            let jitter = Float.random(in: -0.04...0.04)
            let target = targetRMS * weights[i] * (1.0 + jitter)
            let coeff  = target > smoothed[i] ? attackCoeff : releaseCoeff
            smoothed[i] += coeff * (target - smoothed[i])
            smoothed[i]  = max(0, min(1, smoothed[i]))

            let h = minBarH + CGFloat(smoothed[i]) * (maxBarH - minBarH)
            let x = startX + CGFloat(i) * (barWidth + barGap)
            let y = (bounds.height - h) / 2
            barLayers[i].frame = CGRect(x: x, y: y, width: barWidth, height: h)
        }

        CATransaction.commit()
    }

    private func layoutBars() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let totalW = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
        let startX = (bounds.width - totalW) / 2
        for i in 0..<barCount {
            let x = startX + CGFloat(i) * (barWidth + barGap)
            barLayers[i].frame = CGRect(x: x, y: (bounds.height - minBarH) / 2,
                                        width: barWidth, height: minBarH)
        }
        CATransaction.commit()
    }

    deinit {
        timer?.invalidate()
    }
}
