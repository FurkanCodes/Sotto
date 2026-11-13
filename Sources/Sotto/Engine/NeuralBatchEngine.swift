import FluidAudio
import Foundation

/// Catalog models that transcribe whole pieces (not streams) on the Neural
/// Engine, through FluidAudio's CoreML builds: Parakeet v2, Parakeet Ultra and
/// Parakeet TDT-CTC 110M. Dictations reach them in pieces cut at pauses, like
/// the built-in Parakeet v3.
actor NeuralBatchEngine: SpeechEngine {
    enum Kind: Hashable, Sendable {
        case parakeetV2, parakeetUltra, parakeetTdtCtc110m

        var version: AsrModelVersion {
            switch self {
            case .parakeetV2: .v2
            case .parakeetUltra: .ultra
            case .parakeetTdtCtc110m: .tdtCtc110m
            }
        }
    }

    private static let sampleRate = 16_000

    private var asr: AsrManager?
    private var loadedFrom: (kind: Kind, directory: URL)?
    private var kind: Kind?
    private var directory: URL?

    var isLoaded: Bool { asr != nil && loadedFrom?.kind == kind && loadedFrom?.directory == directory }

    /// The model kind and its folder of pinned CoreML files from ModelStore.
    func configure(kind: Kind, directory: URL) {
        self.kind = kind
        self.directory = directory
    }

    func load() async throws {
        if isLoaded { return }
        guard let kind, let directory else { throw EngineError.notLoaded }
        await unload()
        // The first load compiles the models for this Mac's Neural Engine;
        // CoreML caches the result.
        let models = try AsrModels.loadLocal(from: directory, version: kind.version)
        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        self.asr = asr
        loadedFrom = (kind, directory)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await load()
        guard let asr else { throw EngineError.notLoaded }
        // Parakeet rejects audio under a second; pad short clips with silence.
        var audio = samples
        if audio.count < Self.sampleRate {
            audio += [Float](repeating: 0, count: Self.sampleRate - audio.count)
        }
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        return try await asr.transcribe(audio, decoderState: &state).text
    }

    /// Runs one second of silence through the loaded model, so the Neural
    /// Engine is awake when the user lets go (as for the built-in model).
    func warmUp() async {
        guard let asr else { return }
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        _ = try? await asr.transcribe([Float](repeating: 0, count: Self.sampleRate), decoderState: &state)
    }

    func unload() async {
        await asr?.cleanup()
        asr = nil
        loadedFrom = nil
    }
}
