import Foundation

/// The speech models Sotto can download and run through transcribe.cpp.
/// The list is Handy's catalog (MIT), bundled as model-catalog.json, so it
/// works with no network access: every file is pinned to a Hugging Face
/// revision with its size and SHA-256.
struct CatalogModel: Decodable, Identifiable, Hashable, Sendable {
    struct File: Decodable, Hashable, Sendable {
        let filename: String
        let size: Int64
        let sha256: String
    }

    struct Capabilities: Decodable, Hashable, Sendable {
        let streaming: Bool?
        let languageDetection: Bool?
    }

    let id: String
    let name: String
    let description: String?
    let repository: String
    let revision: String
    let license: String?
    let family: String
    let parameters: String?
    let languages: [String]
    let capabilities: Capabilities?
    let quant: String
    let role: String
    let curated: Bool?
    let files: [String: File]

    /// The file for the catalog's default quantization.
    var file: File? { files[quant] ?? files.values.min { $0.size < $1.size } }

    var downloadURL: URL? {
        guard let file else { return nil }
        return URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file.filename)")
    }

    /// "English", "25 languages, including Turkish".
    var languageSummary: String {
        let codes = languages.map { $0.split(separator: "-").first.map(String.init) ?? $0 }
        if Set(codes) == ["en"] { return "English" }
        if codes.count == 1, let name = Locale.current.localizedString(forLanguageCode: codes[0]) { return name }
        let turkish = codes.contains("tr") ? ", including Turkish" : ""
        return "\(Set(codes).count) languages\(turkish)"
    }

    var isMultilingual: Bool { Set(languages.map { $0.prefix(2) }).count > 1 }

    /// Built to transcribe as audio arrives, and measured in Sotto: the
    /// Parakeet family (Nemotron, Parakeet Unified). Moonshine's streaming
    /// decodes the whole recording again on every feed, and Voxtral Realtime
    /// hasn't been measured, so those still use pause-cut pieces.
    var streams: Bool { (capabilities?.streaming ?? false) && family == "parakeet" }

    /// The model's own tag for a language code: "tr" is "tr-TR" for
    /// Nemotron, which rejects plain "tr", and stays "tr" for Whisper.
    func languageTag(for code: String) -> String? {
        languages.first { $0 == code } ?? languages.first { $0.hasPrefix(code + "-") }
    }

    /// The catalog model a downloaded file belongs to.
    static func model(forFile path: String) -> CatalogModel? {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return ModelCatalog.models.first { $0.files.values.contains { $0.filename == name } }
    }

    var familyTitle: String {
        switch family {
        case "parakeet": "Parakeet and Nemotron"
        case "whisper": "Whisper"
        case "moonshine", "moonshine_streaming": "Moonshine"
        case "canary", "canary_qwen": "Canary"
        case "granite5_ctc", "granite_speech", "granite_speech_nar": "Granite"
        case "voxtral", "voxtral_realtime": "Voxtral"
        case "qwen3_asr": "Qwen3 ASR"
        case "cohere_asr": "Cohere"
        case "gigaam": "GigaAM"
        case "funasr_nano": "Fun-ASR"
        case "sensevoice": "SenseVoice"
        case "medasr": "MedASR"
        default: family.capitalized
        }
    }
}

enum ModelCatalog {
    /// Handy's recommended order (catalog/mod.rs HANDY_RANKING); everything
    /// else follows, curated models first.
    private static let ranking = [
        "parakeet-unified-en-0.6b", "nemotron-3.5-asr-streaming-0.6b", "canary-180m-flash",
        "cohere-transcribe-03-2026", "whisper-medium", "Voxtral-Mini-4B-Realtime-2602",
        "parakeet-tdt-0.6b-v3", "parakeet-tdt-0.6b-v2", "Qwen3-ASR-0.6B", "Fun-ASR-MLT-Nano-2512",
    ]

    /// Speech models only, in recommended order.
    static let models: [CatalogModel] = {
        struct Root: Decodable { let models: [CatalogModel] }
        guard let url = Bundle.main.url(forResource: "model-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(Root.self, from: data)
        else { return [] }
        // Parakeet v3 is the built-in model, already on the Neural Engine.
        return root.models.filter { $0.role == "asr" && $0.file != nil && $0.id != "parakeet-tdt-0.6b-v3" }.sorted { a, b in
            let rankA = ranking.firstIndex(of: a.id) ?? Int.max
            let rankB = ranking.firstIndex(of: b.id) ?? Int.max
            if rankA != rankB { return rankA < rankB }
            if (a.curated ?? false) != (b.curated ?? false) { return a.curated ?? false }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }()

    static func model(id: String) -> CatalogModel? {
        models.first { $0.id == id }
    }

    static func isRecommended(_ model: CatalogModel) -> Bool {
        ranking.prefix(5).contains(model.id)
    }
}
