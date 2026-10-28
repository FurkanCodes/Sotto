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
        let samples = try AudioConverter().resampleAudioFile(path: path)
        let clock = ContinuousClock()
        let engine = ParakeetEngine()
        let voice = VoiceDetector()

        let loadTime = try await clock.measure {
            try await voice.load()
            try await engine.load()
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
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
