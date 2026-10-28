import AVFoundation
import Synchronization

/// Records the default input as 16 kHz mono Float32. The mic is open only
/// between `start` and `stop`; a fresh engine per recording picks up device
/// changes without listening for them.
@MainActor
final class AudioRecorder {
    enum RecorderError: Error {
        case noInputDevice
        case unsupportedFormat
    }

    private var engine: AVAudioEngine?
    private var capture: CaptureBuffer?

    /// `onFirstAudio` fires once, when the first real audio arrives. Bluetooth
    /// mics can take seconds to deliver it (Handy managers/audio.rs).
    /// `onAudio` receives each converted chunk, in order, on the audio thread.
    func start(
        onFirstAudio: @escaping @Sendable () -> Void,
        onLevel: @escaping @Sendable (Float) -> Void,
        onAudio: @escaping @Sendable ([Float]) -> Void
    ) throws {
        _ = stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw RecorderError.noInputDevice }
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: target)
        else { throw RecorderError.unsupportedFormat }

        let capture = CaptureBuffer(
            converter: converter, target: target, onFirstAudio: onFirstAudio, onLevel: onLevel, onAudio: onAudio
        )
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat, block: capture.makeTapBlock())
        engine.prepare()
        try engine.start()
        self.engine = engine
        self.capture = capture
    }

    /// Returns everything recorded and closes the mic. Stopping the engine
    /// can take tens of milliseconds, so it happens off the main thread and
    /// never delays transcription.
    func stop() -> [Float] {
        guard let engine else { return [] }
        let samples = capture?.drain() ?? []
        capture = nil
        self.engine = nil
        nonisolated(unsafe) let closing = engine
        DispatchQueue.global(qos: .utility).async {
            closing.inputNode.removeTap(onBus: 0)
            closing.stop()
        }
        return samples
    }
}

/// Converts and stores audio on the tap's thread. The converter is touched
/// only from that thread; the samples are behind a lock.
private final class CaptureBuffer: @unchecked Sendable {
    private struct State {
        var samples: [Float] = []
        var heardAudio = false
    }

    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private let state = Mutex(State())
    private let onFirstAudio: @Sendable () -> Void
    private let onLevel: @Sendable (Float) -> Void
    private let onAudio: @Sendable ([Float]) -> Void

    init(
        converter: AVAudioConverter,
        target: AVAudioFormat,
        onFirstAudio: @escaping @Sendable () -> Void,
        onLevel: @escaping @Sendable (Float) -> Void,
        onAudio: @escaping @Sendable ([Float]) -> Void
    ) {
        self.converter = converter
        self.target = target
        self.onFirstAudio = onFirstAudio
        self.onLevel = onLevel
        self.onAudio = onAudio
    }

    /// Built here, outside the main actor, because the tap calls it on an
    /// audio thread.
    func makeTapBlock() -> AVAudioNodeTapBlock {
        { [self] buffer, _ in consume(buffer) }
    }

    func drain() -> [Float] {
        state.withLock { state in
            defer { state.samples = [] }
            return state.samples
        }
    }

    private func consume(_ input: AVAudioPCMBuffer) {
        let ratio = target.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        let feeder = OneShotFeeder(input)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard let buffer = feeder.take() else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = output.floatChannelData?[0], output.frameLength > 0 else { return }

        let chunk = UnsafeBufferPointer(start: channel, count: Int(output.frameLength))
        var sumOfSquares: Float = 0
        for sample in chunk { sumOfSquares += sample * sample }
        let rms = (sumOfSquares / Float(chunk.count)).squareRoot()

        let isFirst = state.withLock { state in
            state.samples.append(contentsOf: chunk)
            defer { state.heardAudio = true }
            return !state.heardAudio
        }
        if isFirst { onFirstAudio() }
        onLevel(rms)
        onAudio(Array(chunk))
    }
}

/// Hands one buffer to the converter, then reports no more data, so the
/// converter keeps its resampling state between buffers.
private final class OneShotFeeder: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
