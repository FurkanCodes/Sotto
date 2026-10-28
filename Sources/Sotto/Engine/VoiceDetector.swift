import FluidAudio

/// Silero voice detection through FluidAudio. Cuts silence out of a recording
/// before transcription, so the model gets less audio and can't invent words
/// in quiet stretches.
actor VoiceDetector {
    static let sampleRate = 16_000
    /// One Silero window: 4096 samples, 256 ms.
    static let windowSize = VadManager.chunkSize
    /// Silence kept around speech. FluidAudio pads by `speechPadding`, which
    /// must stay at or below its 0.15 s minimum speech length, so the rest of
    /// Handy's 450 ms (audio_toolkit/vad) is added here.
    static let extraPadding = Int(0.35 * Double(sampleRate))
    private static let segmentation: VadSegmentationConfig = {
        var config = VadSegmentationConfig.default
        config.speechPadding = 0.1
        return config
    }()

    private var manager: VadManager?

    var isLoaded: Bool { manager != nil }

    /// Downloads the model on first use.
    func load() async throws {
        if manager == nil {
            manager = try await VadManager(config: .default)
        }
    }

    func unload() {
        manager = nil
    }

    /// Runs one model window of silence, so detection starts warm.
    func warmUp() async {
        _ = try? await manager?.process([Float](repeating: 0, count: Self.windowSize))
    }

    /// Feeds one 256 ms window through Silero, carrying `state` between calls.
    /// The result's event marks where speech started or ended. Returns nil if
    /// the model isn't loaded.
    func stream(_ window: [Float], state: VadStreamState) async throws -> VadStreamResult? {
        guard let manager else { return nil }
        return try await manager.processStreamingChunk(window, state: state, config: Self.segmentation)
    }

    /// The speech parts of a whole recording, each padded by about 450 ms.
    /// Returns nil when there is no speech at all. If detection isn't
    /// available or fails, everything counts as speech.
    func speech(in samples: [Float]) async -> [Float]? {
        guard let manager, !samples.isEmpty else { return samples }
        do {
            let segments = try await manager.segmentSpeech(samples, config: Self.segmentation)
            guard !segments.isEmpty else { return nil }
            let ranges = segments.map {
                ($0.startSample(sampleRate: Self.sampleRate) - Self.extraPadding)..<($0.endSample(sampleRate: Self.sampleRate) + Self.extraPadding)
            }
            let speech = Self.join(ranges, in: samples)
            return speech.isEmpty ? samples : speech
        } catch {
            Log.app.error("Voice detection failed, keeping all audio: \(error.localizedDescription, privacy: .public)")
            return samples
        }
    }

    /// Concatenates `ranges` of `samples`, clamped to the audio and with
    /// overlaps removed, so no stretch is used twice.
    static func join(_ ranges: [Range<Int>], in samples: [Float]) -> [Float] {
        var result: [Float] = []
        var covered = 0
        for range in ranges {
            let start = max(range.lowerBound, covered, 0)
            let end = min(range.upperBound, samples.count)
            guard start < end else { continue }
            result.append(contentsOf: samples[start..<end])
            covered = end
        }
        return result
    }
}
