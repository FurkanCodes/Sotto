import FluidAudio

/// A speech-to-text engine. Parakeet on CoreML is the default; transcribe-cpp
/// models will implement this from an XPC helper in a later phase.
protocol SpeechEngine: Actor {
    var isLoaded: Bool { get }
    func load() async throws
    /// 16 kHz mono samples in, raw transcript out.
    func transcribe(_ samples: [Float]) async throws -> String
    func unload() async
}

enum EngineError: Error {
    case notLoaded
}

/// Parakeet TDT 0.6B v3 through FluidAudio, preferring the Neural Engine.
actor ParakeetEngine: SpeechEngine {
    private static let version = AsrModelVersion.v3
    private static let sampleRate = 16_000

    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?

    var isLoaded: Bool { manager != nil }

    nonisolated var isDownloaded: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: Self.version), version: Self.version)
    }

    /// The one network call Sotto makes: fetching the pinned model files.
    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        try await AsrModels.download(version: Self.version) { progress($0.fractionCompleted) }
    }

    func load() async throws {
        if manager != nil { return }
        if let loading {
            manager = try await loading.value
            return
        }
        let task = Task { () throws -> AsrManager in
            let models = try await AsrModels.downloadAndLoad(version: Self.version)
            let asr = AsrManager(config: .default)
            try await asr.loadModels(models)
            // The first run after a load is slower; pay for it now, while the
            // user is still talking, not after they let go.
            var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
            _ = try? await asr.transcribe([Float](repeating: 0, count: Self.sampleRate), decoderState: &state)
            return asr
        }
        loading = task
        defer { loading = nil }
        manager = try await task.value
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await load()
        guard let manager else { throw EngineError.notLoaded }
        // Parakeet rejects audio under a second; pad short clips with silence.
        var audio = samples
        if audio.count < Self.sampleRate {
            audio += [Float](repeating: 0, count: Self.sampleRate - audio.count)
        }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        return try await manager.transcribe(audio, decoderState: &state).text
    }

    func unload() async {
        await manager?.cleanup()
        manager = nil
    }

    /// Runs one second of silence through the loaded model. Called when the
    /// user presses the key, so the Neural Engine is awake by the time they
    /// let go. Does nothing if the model isn't loaded.
    func warmUp() async {
        guard let manager else { return }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        _ = try? await manager.transcribe([Float](repeating: 0, count: Self.sampleRate), decoderState: &state)
    }
}
