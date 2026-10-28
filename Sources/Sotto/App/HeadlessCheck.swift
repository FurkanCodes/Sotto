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
        let engine: any SpeechEngine
        var streams = false
        if let index = CommandLine.arguments.firstIndex(of: "--model"), index + 1 < CommandLine.arguments.count {
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
            if streams, let helper = engine as? HelperEngine {
                let lookahead = CommandLine.arguments.firstIndex(of: "--lookahead").flatMap { CommandLine.arguments[safe: $0 + 1] }.flatMap { Int($0) } ?? 0
                live = StreamingTranscriber(engine: helper, voice: voice, id: run, lookaheadMs: lookahead) { _ in captions.count() }
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
        let json = try JSONSerialization.data(withJSONObject: ["audio_seconds": Double(samples.count) / 16_000, "runs": runs], options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))
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
