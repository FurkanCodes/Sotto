import AVFoundation
import FluidAudio
import Synchronization

/// Streaming models on the Neural Engine, through FluidAudio's CoreML builds:
/// Parakeet Unified and both Nemotrons. Each runs at one fixed latency,
/// because every setting is a separate ~600 MB encoder. Measurements against
/// the same models on the GPU are in docs/measurements.md.
actor NeuralStreamEngine: StreamingSpeechEngine {
    enum Kind: Hashable, Sendable {
        /// Parakeet Unified, 320 ms ([70, 2, 2]).
        case parakeetUnified
        /// Nemotron Speech Streaming (English), with this chunk size in ms.
        case nemotronEnglish(chunkMs: Int)
        /// Nemotron 3.5 Streaming (multilingual), with this chunk size in ms.
        case nemotronMultilingual(chunkMs: Int)

        var latencyMs: Int {
            switch self {
            case .parakeetUnified: Self.unifiedConfig.latencyMs
            case .nemotronEnglish(let chunk), .nemotronMultilingual(let chunk): chunk
            }
        }

        static let unifiedConfig = StreamingModelVariant.parakeetUnified320ms.unifiedConfig ?? UnifiedConfig()
    }

    private enum Manager {
        case unified(StreamingUnifiedAsrManager)
        case nemotron(StreamingNemotronAsrManager)
        case multilingual(StreamingNemotronMultilingualAsrManager)
    }

    private var manager: Manager?
    private var kind: Kind?
    private var directory: URL?
    private var language: String?
    private var loaded: (kind: Kind, directory: URL)?
    private var streamID: Int?

    var isLoaded: Bool { manager != nil && loaded?.kind == kind && loaded?.directory == directory }

    /// Set from the model being configured; streams read it for batching.
    private nonisolated let latency = Mutex<Int?>(nil)
    nonisolated var fixedLookaheadMs: Int? { latency.withLock { $0 } }

    /// The model kind and its folder of pinned CoreML files from ModelStore,
    /// and for multilingual Nemotron a language tag like "tr-TR" (nil detects
    /// it). A new kind or folder takes effect on the next load.
    func configure(kind: Kind, directory: URL, language: String?) async {
        self.kind = kind
        self.directory = directory
        latency.withLock { $0 = kind.latencyMs }
        if language != self.language {
            self.language = language
            if case .multilingual(let manager) = manager { await manager.setLanguage(language) }
        }
    }

    func load() async throws {
        if isLoaded { return }
        guard let kind, let directory else { throw EngineError.notLoaded }
        await unload()
        // The first load compiles the encoder for this Mac's Neural Engine
        // (about 25 s); CoreML caches the result.
        switch kind {
        case .parakeetUnified:
            let unified = StreamingUnifiedAsrManager(config: Kind.unifiedConfig)
            try await unified.loadModels(from: directory)
            manager = .unified(unified)
        case .nemotronEnglish(let chunkMs):
            let nemotron = StreamingNemotronAsrManager(requestedChunkSize: NemotronChunkSize(rawValue: chunkMs))
            try await nemotron.loadModels(from: directory)
            manager = .nemotron(nemotron)
        case .nemotronMultilingual:
            let multilingual = StreamingNemotronMultilingualAsrManager()
            try await multilingual.loadModels(from: directory)
            await multilingual.setLanguage(language)
            manager = .multilingual(multilingual)
        }
        loaded = (kind, directory)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await load()
        streamID = nil
        try await reset()
        _ = try await feed(samples)
        return try await finish()
    }

    /// Does nothing: the stream starts with the first audio, which wakes the
    /// Neural Engine anyway, and a warm-up run would end that stream.
    func warmUp() async {}

    func unload() async {
        switch manager {
        case .unified(let unified): await unified.cleanup()
        case .nemotron(let nemotron): await nemotron.cleanup()
        case .multilingual(let multilingual): await multilingual.cleanup()
        case nil: break
        }
        manager = nil
        loaded = nil
        streamID = nil
    }

    func beginStream(id: Int, lookaheadMs: Int) async throws {
        try await load()
        try await reset()
        streamID = id
    }

    func feedStream(id: Int, _ samples: [Float]) async throws -> String? {
        guard streamID == id, !samples.isEmpty else { return nil }
        return try await feed(samples)
    }

    func finishStream(id: Int) async throws -> String {
        guard streamID == id else { throw EngineError.notLoaded }
        streamID = nil
        return try await finish()
    }

    func cancelStream(id: Int) async {
        guard streamID == id else { return }
        streamID = nil
        try? await reset()
    }

    // MARK: - The three managers

    private func reset() async throws {
        switch manager {
        case .unified(let unified): try await unified.reset()
        case .nemotron(let nemotron): await nemotron.reset()
        case .multilingual(let multilingual): await multilingual.reset()
        case nil: throw EngineError.notLoaded
        }
    }

    /// Adds audio, decodes whatever full chunks it completes, and returns the text so far.
    private func feed(_ samples: [Float]) async throws -> String {
        switch manager {
        case .unified(let unified):
            try await unified.appendAudio(Self.buffer(samples))
            try await unified.processBufferedAudio()
            return await unified.getPartialTranscript()
        case .nemotron(let nemotron):
            _ = try await nemotron.process(audioBuffer: Self.buffer(samples))
            return await nemotron.getPartialTranscript()
        case .multilingual(let multilingual):
            _ = try await multilingual.process(samples: samples)
            return await multilingual.getPartialTranscript()
        case nil:
            throw EngineError.notLoaded
        }
    }

    private func finish() async throws -> String {
        switch manager {
        case .unified(let unified): try await unified.finish()
        case .nemotron(let nemotron): try await nemotron.finish()
        case .multilingual(let multilingual): try await multilingual.finish()
        case nil: throw EngineError.notLoaded
        }
    }

    /// Not isolated to the actor, so the new buffer can be handed to FluidAudio.
    private nonisolated static func buffer(_ samples: [Float]) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { throw EngineError.notLoaded }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
        }
        return buffer
    }
}
