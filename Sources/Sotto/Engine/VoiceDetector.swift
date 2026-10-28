import FluidAudio

/// Silero voice detection through FluidAudio. Cuts silence out of a recording
/// before transcription, so the model gets less audio and can't invent words
/// in quiet stretches.
actor VoiceDetector {
    private static let sampleRate = 16_000
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

    /// Runs one model window of silence, so detection starts warm after release.
    func warmUp() async {
        _ = try? await manager?.process([Float](repeating: 0, count: VadManager.chunkSize))
    }

    /// The speech parts of `samples`, each padded by 450 ms like Handy
    /// (audio_toolkit/vad). Returns nil when there is no speech at all.
    /// If detection isn't available or fails, everything counts as speech.
    func speech(in samples: [Float]) async -> [Float]? {
        guard let manager, !samples.isEmpty else { return samples }
        do {
            var config = VadSegmentationConfig.default
            config.speechPadding = 0.45
            let segments = try await manager.segmentSpeech(samples, config: config)
            guard !segments.isEmpty else { return nil }
            var speech: [Float] = []
            speech.reserveCapacity(samples.count)
            for segment in segments {
                let start = max(0, segment.startSample(sampleRate: Self.sampleRate))
                let end = min(samples.count, segment.endSample(sampleRate: Self.sampleRate))
                if start < end { speech.append(contentsOf: samples[start..<end]) }
            }
            return speech.isEmpty ? samples : speech
        } catch {
            Log.app.error("Voice detection failed, keeping all audio: \(error.localizedDescription, privacy: .public)")
            return samples
        }
    }
}
