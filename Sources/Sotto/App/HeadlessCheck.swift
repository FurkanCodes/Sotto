import AVFoundation
import Foundation
import FluidAudio
import SottoCore

/// `Sotto --transcribe-file <audio> [--repeat N] [--gap S] [--warm]` runs the
/// speech pipeline (voice detection, Parakeet, cleanup) on a file without the
/// mic, hotkey or UI, prints timings and exits. For checking the engine and
/// for the timing harness.
///
/// `--gap` waits S seconds of idle before each run, like real dictations
/// spaced apart. `--warm` also runs the key-down warm-up 2 s before each run,
/// like a press 2 s before release.
enum HeadlessCheck {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        if arguments.contains("--list-models") {
            let models = ModelCatalog.models
            print("\(models.count) speech models in the catalog")
            for model in models.prefix(12) {
                print("  \(model.id) · \(model.familyTitle) · \(model.languageSummary) · \(model.file.map { ByteCountFormatter.string(fromByteCount: $0.size, countStyle: .file) } ?? "?")")
            }
            exit(models.isEmpty ? 1 : 0)
        }
        guard let index = arguments.firstIndex(of: "--transcribe-file"), index + 1 < arguments.count else { return }
        let path = arguments[index + 1]
        let repeats = arguments.firstIndex(of: "--repeat").flatMap { Int(arguments[safe: $0 + 1] ?? "") } ?? 5
        let gap = arguments.firstIndex(of: "--gap").flatMap { Double(arguments[safe: $0 + 1] ?? "") } ?? 0
        let warm = arguments.contains("--warm")
        let warmLead = arguments.firstIndex(of: "--warm-lead").flatMap { Double(arguments[safe: $0 + 1] ?? "") } ?? 2

        Task {
            do {
                try await run(path: path, repeats: repeats, gap: gap, warm: warm, warmLead: warmLead)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("error: \(error)\n".utf8))
                exit(1)
            }
        }
        dispatchMain()
    }

    private static func run(path: String, repeats: Int, gap: Double, warm: Bool, warmLead: Double = 2) async throws {
        let samples = try await MediaReader.samples(from: URL(fileURLWithPath: path))
        let clock = ContinuousClock()
        if let index = CommandLine.arguments.firstIndex(of: "--fluid-stream"),
           let name = CommandLine.arguments[safe: index + 1],
           let chunk = CommandLine.arguments[safe: index + 2].flatMap({ Int($0) }) {
            try await runFluidStream(samples: samples, name: name, chunkMs: chunk, repeats: repeats)
            return
        }
        let engine: any SpeechEngine
        var streams = false
        if let index = CommandLine.arguments.firstIndex(of: "--model-id"),
           let id = CommandLine.arguments[safe: index + 1], let model = ModelCatalog.model(id: id) {
            // The app's path: ModelStore's pinned, checked download, then the engine the app would pick.
            let store = await ModelStore()
            if let flag = CommandLine.arguments.firstIndex(of: "--engine"),
               let engine = CommandLine.arguments[safe: flag + 1].flatMap(ModelEngine.init(rawValue:)) {
                await MainActor.run { store.engine = engine }
            }
            let neuralBuild = await store.neural(for: model)
            let path = try await installed(model, in: store)
            let language = CommandLine.arguments.firstIndex(of: "--language").flatMap { CommandLine.arguments[safe: $0 + 1] }
            if let kind = neuralBuild?.streamKind {
                let neural = NeuralStreamEngine()
                await neural.configure(kind: kind, directory: path, language: language.flatMap(model.languageTag))
                engine = neural
            } else if let kind = neuralBuild?.batchKind {
                let batch = NeuralBatchEngine()
                await batch.configure(kind: kind, directory: path)
                engine = batch
            } else {
                let helper = HelperEngine()
                await helper.configure(modelPath: path.path, language: language.flatMap(model.languageTag), vocabulary: [])
                engine = helper
            }
            streams = model.streams && !CommandLine.arguments.contains("--pieces")
        } else if let index = CommandLine.arguments.firstIndex(of: "--model"), index + 1 < CommandLine.arguments.count {
            let helper = HelperEngine()
            let path = CommandLine.arguments[index + 1]
            let model = CatalogModel.model(forFile: path)
            let language = CommandLine.arguments.firstIndex(of: "--language").flatMap { CommandLine.arguments[safe: $0 + 1] }
            await helper.configure(modelPath: path, language: language.map { model?.languageTag(for: $0) ?? $0 }, vocabulary: [])
            engine = helper
            streams = model?.streams == true && !CommandLine.arguments.contains("--pieces")
        } else {
            engine = ParakeetEngine()
        }
        let voice = VoiceDetector()

        let loadTime = try await clock.measure {
            try await voice.load()
            try await engine.load()
        }

        if CommandLine.arguments.contains("--live") {
            try await runLive(samples: samples, engine: engine, voice: voice, repeats: repeats, streams: streams)
            return
        }

        var vadTimes: [Duration] = []
        var transcribeTimes: [Duration] = []
        var text = ""
        for _ in 0..<max(1, repeats) {
            if gap > 0 {
                let lead = warm ? min(warmLead, gap) : 0
                try await Task.sleep(for: .seconds(gap - lead))
                if warm {
                    await engine.warmUp()
                    await voice.warmUp()
                    try await Task.sleep(for: .seconds(lead))
                }
            }
            var speech: [Float]?
            vadTimes.append(await clock.measure { speech = await voice.speech(in: samples) })
            let audio = speech ?? []
            var raw = ""
            transcribeTimes.append(try await clock.measure { raw = audio.isEmpty ? "" : try await engine.transcribe(audio) })
            text = TextCleanup.clean(raw)
        }

        func milliseconds(_ duration: Duration) -> Int {
            Int((Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000).rounded())
        }
        let result: [String: Any] = [
            "audio_seconds": Double(samples.count) / 16_000,
            "load_ms": milliseconds(loadTime),
            "vad_ms": vadTimes.map(milliseconds),
            "transcribe_ms": transcribeTimes.map(milliseconds),
            "engine": engineName(engine),
            "best_total_ms": zip(vadTimes, transcribeTimes).map { milliseconds($0 + $1) }.min() ?? 0,
            "text": text,
        ]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }

    /// `--live`: feeds the file in at real-time speed, in 64 ms chunks like
    /// the mic, then measures the time from "release" to the final text.
    /// Streaming models stream, unless `--pieces` asks for pause-cut pieces.
    private static func runLive(samples: [Float], engine: any SpeechEngine, voice: VoiceDetector, repeats: Int, streams: Bool) async throws {
        let clock = ContinuousClock()
        let chunk = 1024
        var runs: [[String: Any]] = []
        for run in 0..<max(1, repeats) {
            let captions = Captions()
            let live: any LiveTranscribing
            if streams, let streaming = engine as? any StreamingSpeechEngine {
                let lookahead = CommandLine.arguments.firstIndex(of: "--lookahead").flatMap { CommandLine.arguments[safe: $0 + 1] }.flatMap { Int($0) } ?? 0
                live = StreamingTranscriber(engine: streaming, voice: voice, id: run, lookaheadMs: lookahead) { _ in captions.count() }
            } else {
                live = LiveTranscriber(engine: engine, voice: voice) { _ in captions.count() }
            }
            var offset = 0
            let start = clock.now
            while offset < samples.count {
                let end = min(offset + chunk, samples.count)
                await live.append(Array(samples[offset..<end]))
                offset = end
                try await clock.sleep(until: start + .milliseconds(offset * 1000 / 16_000))
            }
            let releasedAt = clock.now
            let result = try await live.finish(fullAudio: samples)
            let afterRelease = clock.now - releasedAt
            runs.append([
                "release_to_text_ms": milliseconds(afterRelease),
                "pieces_while_talking": result.piecesWhileTalking,
                "tail_seconds": (result.tailSeconds * 10).rounded() / 10,
                "fallback": result.usedFallback,
                "streamed": result.streamed,
                "caption_updates": captions.value,
                "first_caption_ms": captions.first.map { milliseconds($0 - start) } ?? -1,
                "text": TextCleanup.clean(result.text),
            ])
        }
        let json = try JSONSerialization.data(withJSONObject: ["audio_seconds": Double(samples.count) / 16_000, "engine": engineName(engine), "runs": runs], options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }

    /// `--fluid-stream <unified|nemotron-en|nemotron-ml> <chunk ms>`: a
    /// Neural Engine streaming model, fetched with FluidAudio's own
    /// downloader (for measuring only; the app uses ModelStore's pinned,
    /// checked files), then streamed through NeuralStreamEngine like `--live`.
    private static func runFluidStream(samples: [Float], name: String, chunkMs: Int, repeats: Int) async throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = support.appendingPathComponent("FluidAudio/Models", isDirectory: true)
        let language = CommandLine.arguments.firstIndex(of: "--language").flatMap { CommandLine.arguments[safe: $0 + 1] }
        let clock = ContinuousClock()
        let loadStart = clock.now
        let kind: NeuralStreamEngine.Kind
        let directory: URL
        switch name {
        case "unified":
            kind = .parakeetUnified
            let manager = StreamingUnifiedAsrManager(config: NeuralStreamEngine.Kind.unifiedConfig)
            try await manager.loadModels()
            await manager.cleanup()
            directory = base.appendingPathComponent(Repo.parakeetUnified.folderName)
        case "nemotron-en":
            guard let size = NemotronChunkSize(rawValue: chunkMs) else { throw EngineError.notLoaded }
            kind = .nemotronEnglish(chunkMs: chunkMs)
            let manager = StreamingNemotronAsrManager(requestedChunkSize: size)
            try await manager.loadModels()
            await manager.cleanup()
            directory = base.appendingPathComponent(size.repo.folderName)
        case "nemotron-ml":
            kind = .nemotronMultilingual(chunkMs: chunkMs)
            directory = try await StreamingNemotronMultilingualAsrManager.downloadVariant(languageCode: language ?? "auto", chunkMs: chunkMs)
        default:
            throw NSError(domain: "Sotto", code: 1, userInfo: [NSLocalizedDescriptionKey: "Use unified, nemotron-en or nemotron-ml"])
        }
        let engine = NeuralStreamEngine()
        await engine.configure(kind: kind, directory: directory, language: language)
        try await engine.load()
        let loadTime = clock.now - loadStart
        let voice = VoiceDetector()
        try await voice.load()
        var runs: [[String: Any]] = []
        for run in 0..<max(1, repeats) {
            let captions = Captions()
            let live = StreamingTranscriber(engine: engine, voice: voice, id: run) { _ in captions.count() }
            let cpuStart = processCPUSeconds()
            var offset = 0
            let start = clock.now
            while offset < samples.count {
                let end = min(offset + 1024, samples.count)
                await live.append(Array(samples[offset..<end]))
                offset = end
                try await clock.sleep(until: start + .milliseconds(offset * 1000 / 16_000))
            }
            let releasedAt = clock.now
            let result = try await live.finish(fullAudio: samples)
            runs.append([
                "release_to_text_ms": milliseconds(clock.now - releasedAt),
                "first_caption_ms": captions.first.map { milliseconds($0 - start) } ?? -1,
                "caption_updates": captions.value,
                "cpu_seconds": ((processCPUSeconds() - cpuStart) * 100).rounded() / 100,
                "streamed": result.streamed,
                "text": TextCleanup.clean(result.text),
            ])
        }
        let result: [String: Any] = [
            "audio_seconds": Double(samples.count) / 16_000, "load_ms": milliseconds(loadTime),
            "directory": directory.path, "runs": runs,
        ]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }

    /// Downloads the model through ModelStore if needed, printing progress,
    /// and returns where it's installed.
    @MainActor
    private static func installed(_ model: CatalogModel, in store: ModelStore) async throws -> URL {
        guard let path = store.path(for: model) else { throw EngineError.notLoaded }
        if store.isInstalled(model) { return path }
        store.download(model)
        var last = -1
        while true {
            switch store.downloads[model.id] {
            case .running(let fraction):
                let percent = Int(fraction * 100)
                if percent / 10 != last / 10 { FileHandle.standardError.write(Data("download \(percent)%\n".utf8)) }
                last = percent
            case .checking:
                break
            case .failed(let message):
                throw NSError(domain: "Sotto", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
            case nil:
                if store.isInstalled(model) { return path }
                throw NSError(domain: "Sotto", code: 3, userInfo: [NSLocalizedDescriptionKey: "Download stopped"])
            }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    /// Which engine ran, so a result can't be mistaken for another engine's.
    private static func engineName(_ engine: any SpeechEngine) -> String {
        switch engine {
        case is NeuralStreamEngine, is NeuralBatchEngine: "neural-engine"
        case is HelperEngine: "gpu"
        default: "built-in"
        }
    }

    /// CPU time this process has used, user plus system, in seconds.
    private static func processCPUSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1e6 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int((Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000).rounded())
    }
}

/// Counts live-caption updates, from whichever thread they arrive on.
private final class Captions: @unchecked Sendable {
    private let lock = NSLock()
    private var updates = 0
    private var firstAt: ContinuousClock.Instant?

    var value: Int { lock.withLock { updates } }
    var first: ContinuousClock.Instant? { lock.withLock { firstAt } }

    func count() {
        lock.withLock {
            updates += 1
            if firstAt == nil { firstAt = .now }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
