import AVFoundation

final class AudioEngine {
    private let engine = AVAudioEngine()
    private(set) var isRunning = false
    private var shouldForward = false

    // Buffer accumulation for Whisper mode (thread-safe)
    private var accumulatedBuffers: [AVAudioPCMBuffer] = []
    private let bufferLock = NSLock()
    private(set) var isAccumulating = false

    var onRMSLevel: ((Float) -> Void)?
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    func start(accumulate: Bool = false) throws {
        guard !isRunning else { return }

        isAccumulating = accumulate
        if accumulate {
            bufferLock.lock()
            accumulatedBuffers.removeAll()
            bufferLock.unlock()
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        shouldForward = true
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, self.shouldForward else { return }

            let rms = self.calculateRMS(buffer)
            DispatchQueue.main.async { self.onRMSLevel?(rms) }

            if self.isAccumulating, let copy = self.copyBuffer(buffer) {
                self.bufferLock.lock()
                self.accumulatedBuffers.append(copy)
                self.bufferLock.unlock()
            }

            self.onAudioBuffer?(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        shouldForward = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    /// Snapshot current accumulated audio as WAV (non-destructive, for streaming chunks).
    func snapshotWAV() -> Data? {
        bufferLock.lock()
        let buffers = Array(accumulatedBuffers)
        bufferLock.unlock()
        guard !buffers.isEmpty else { return nil }
        return convertToWAV(buffers)
    }

    /// Export accumulated audio as WAV and clear buffers (for final result).
    func exportWAV() -> Data? {
        bufferLock.lock()
        let buffers = accumulatedBuffers
        accumulatedBuffers.removeAll()
        bufferLock.unlock()
        isAccumulating = false
        guard !buffers.isEmpty else { return nil }
        return convertToWAV(buffers)
    }

    // MARK: - Private

    private func convertToWAV(_ buffers: [AVAudioPCMBuffer]) -> Data? {
        let inputFormat = buffers[0].format

        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: 16000,
                                               channels: 1,
                                               interleaved: true) else { return nil }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }

        let totalInputFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        let ratio = 16000.0 / inputFormat.sampleRate
        let estimatedOutputFrames = AVAudioFrameCount(Double(totalInputFrames) * ratio) + 4096

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                                   frameCapacity: estimatedOutputFrames) else { return nil }

        var bufferIndex = 0
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            guard bufferIndex < buffers.count else {
                outStatus.pointee = .endOfStream
                return nil
            }
            let buf = buffers[bufferIndex]
            bufferIndex += 1
            outStatus.pointee = .haveData
            return buf
        }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        if let error {
            print("[AudioEngine] Conversion error: \(error)")
            return nil
        }

        return buildWAV(from: outputBuffer)
    }

    private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format,
                                           frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<Int(buffer.format.channelCount) {
                memcpy(dst[ch], src[ch], Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        }
        return copy
    }

    private func buildWAV(from buffer: AVAudioPCMBuffer) -> Data? {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sampleRate: UInt32 = 16000
        let bytesPerSample = bitsPerSample / 8
        let dataSize = UInt32(buffer.frameLength) * UInt32(numChannels) * UInt32(bytesPerSample)
        let fileSize = 36 + dataSize

        var data = Data()
        data.reserveCapacity(Int(44 + dataSize))

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        appendUInt32LE(&data, fileSize)
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        appendUInt32LE(&data, 16)
        appendUInt16LE(&data, 1)               // PCM format
        appendUInt16LE(&data, numChannels)
        appendUInt32LE(&data, sampleRate)
        appendUInt32LE(&data, sampleRate * UInt32(numChannels) * UInt32(bytesPerSample))
        appendUInt16LE(&data, numChannels * bytesPerSample)
        appendUInt16LE(&data, bitsPerSample)

        // data chunk
        data.append(contentsOf: "data".utf8)
        appendUInt32LE(&data, dataSize)

        if let int16Data = buffer.int16ChannelData {
            let byteCount = Int(buffer.frameLength) * MemoryLayout<Int16>.size
            data.append(contentsOf: UnsafeRawBufferPointer(start: int16Data[0], count: byteCount))
        }

        return data
    }

    private func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private func appendUInt16LE(_ data: inout Data, _ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }

        let frames = Int(buffer.frameLength)
        let samples = channelData[0]

        var sumOfSquares: Float = 0
        for i in 0..<frames {
            let s = samples[i]
            sumOfSquares += s * s
        }

        let rms = sqrt(sumOfSquares / Float(frames))
        return min(rms * 5.0, 1.0)
    }
}
