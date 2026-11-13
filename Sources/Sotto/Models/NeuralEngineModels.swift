import Foundation
import SottoCore

/// A catalog model that runs on the Neural Engine through FluidAudio's CoreML
/// build instead of on the GPU through transcribe.cpp. Listed in
/// neural-engine-models.json (written by scripts/pin-neural-models.py) with a
/// pinned Hugging Face commit and the size and SHA-256 of every file.
struct NeuralModel: Decodable, Hashable, Sendable {
    struct File: Decodable, Hashable, Sendable {
        let path: String
        let size: Int64
        let sha256: String
    }

    enum Engine: String, Decodable, Sendable {
        case parakeetUnifiedStream = "parakeet-unified-stream"
        case nemotronEnglishStream = "nemotron-en-stream"
        case nemotronMultilingualStream = "nemotron-multilingual-stream"
        case parakeetV2 = "parakeet-v2"
        case parakeetUltra = "parakeet-ultra"
        case parakeetTdtCtc110m = "parakeet-tdt-ctc-110m"
        /// The built-in Parakeet v3 and the voice detector.
        case builtIn = "built-in"
    }

    let catalogID: String
    let engine: Engine
    let repository: String
    let revision: String
    /// The repository folder that holds this model's files, if not the top.
    let root: String?
    /// The chunk size the files were built for, for models that have several.
    let chunkMs: Int?
    /// False when this build measured worse than the GPU build, so Automatic
    /// skips it; "Neural Engine" in Settings still uses it.
    let automatic: Bool?
    let size: Int64
    let files: [File]

    /// For streaming models: how NeuralStreamEngine runs it.
    var streamKind: NeuralStreamEngine.Kind? {
        switch engine {
        case .parakeetUnifiedStream: .parakeetUnified
        case .nemotronEnglishStream: .nemotronEnglish(chunkMs: chunkMs ?? 1120)
        case .nemotronMultilingualStream: .nemotronMultilingual(chunkMs: chunkMs ?? 1120)
        default: nil
        }
    }

    /// For models that transcribe whole pieces: how NeuralBatchEngine runs it.
    var batchKind: NeuralBatchEngine.Kind? {
        switch engine {
        case .parakeetV2: .parakeetV2
        case .parakeetUltra: .parakeetUltra
        case .parakeetTdtCtc110m: .parakeetTdtCtc110m
        default: nil
        }
    }

    /// Where a file goes inside the model's folder: its path below `root`.
    func localPath(for file: File) -> String {
        guard let root, file.path.hasPrefix(root + "/") else { return file.path }
        return String(file.path.dropFirst(root.count + 1))
    }

    func url(for file: File) -> URL? {
        let path = file.path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        return URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(path)")
    }

    /// The model's folder: a new pinned commit downloads into a new folder.
    var folderName: String {
        "\(repository.split(separator: "/").last ?? "model")-\(revision.prefix(10))"
    }
}

enum NeuralEngineModels {
    private struct Root: Decodable {
        let models: [NeuralModel]
        let builtIn: [NeuralModel]
    }

    private static let root: Root? = {
        guard let url = Bundle.main.url(forResource: "neural-engine-models", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Root.self, from: data)
    }()

    /// Catalog models with a Neural Engine build.
    static var all: [NeuralModel] { root?.models ?? [] }

    static func model(for catalogID: String) -> NeuralModel? {
        all.first { $0.catalogID == catalogID }
    }

    /// The built-in Parakeet v3 ("parakeet-tdt-0.6b-v3") and the voice detector ("silero-vad").
    static func builtIn(_ id: String) -> NeuralModel? {
        root?.builtIn.first { $0.catalogID == id }
    }

    /// Where pinned model folders live: Application Support/Sotto/Models.
    static let folder: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Sotto/Models", isDirectory: true)
    }()
}

enum Hardware {
    /// Apple silicon has a Neural Engine; Intel Macs don't.
    static let hasNeuralEngine: Bool = {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }()
}

extension CatalogModel {
    /// The model's Neural Engine build, if there is one.
    var neuralBuild: NeuralModel? { NeuralEngineModels.model(for: id) }

    /// The Neural Engine build to use under this setting, or nil for the GPU build.
    func neural(for engine: ModelEngine) -> NeuralModel? {
        guard Hardware.hasNeuralEngine, let build = neuralBuild else { return nil }
        switch engine {
        case .gpu: return nil
        case .neuralEngine: return build
        case .automatic: return build.automatic == false ? nil : build
        }
    }
}
