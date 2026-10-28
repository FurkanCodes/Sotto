/// One dictation transcribed while the user talks: in pieces cut at pauses
/// (`LiveTranscriber`), or as a live stream (`StreamingTranscriber`).
protocol LiveTranscribing: Actor {
    /// Called in order with each chunk of 16 kHz audio while recording.
    func append(_ samples: [Float]) async
    /// Transcribes what's left and returns the whole text. `fullAudio` is
    /// the complete recording; the stream can miss the last buffer.
    func finish(fullAudio: [Float]) async throws -> LiveTranscriber.Result
    func cancel() async
}

/// Transcribes one dictation as a live stream, for models built to stream
/// (Nemotron, Parakeet Unified). The helper decodes the audio as it arrives,
/// so at release only the model's last chunk is left, even when the user
/// never pauses. Pause-cut pieces can't do that: speech without a pause
/// stays in one piece and is all transcribed after release.
///
/// If the stream can't start or fails, `finish` transcribes the whole
/// recording at once instead.
actor StreamingTranscriber: LiveTranscribing {
    private enum State {
        case notStarted, streaming, failed
    }

    /// Audio is sent in batches of at least 256 ms: four mic buffers per
    /// message instead of one. Nemotron decodes in 1.12 s chunks anyway.
    private static let minFeed = 4096

    private let engine: HelperEngine
    private let voice: VoiceDetector
    private let id: Int
    /// Called with the whole text so far each time it changes.
    private let onText: (@Sendable (String) -> Void)?
    private var audio: [Float] = []
    private var fed = 0
    private var state = State.notStarted
    private var lastText = ""

    init(engine: HelperEngine, voice: VoiceDetector, id: Int, onText: (@Sendable (String) -> Void)? = nil) {
        self.engine = engine
        self.voice = voice
        self.id = id
        self.onText = onText
    }

    func append(_ samples: [Float]) async {
        audio.append(contentsOf: samples)
        if state == .notStarted {
            // The first chunk waits for the model to load; later chunks queue behind it.
            do {
                try await engine.beginStream(id: id)
                state = .streaming
            } catch {
                fail("start", error)
            }
        }
        guard state == .streaming, audio.count - fed >= Self.minFeed else { return }
        await feedRest()
    }

    func finish(fullAudio: [Float]) async throws -> LiveTranscriber.Result {
        let clock = ContinuousClock()
        if fullAudio.count > audio.count {
            audio = fullAudio
        }
        let start = clock.now
        if state == .streaming {
            await feedRest()
        }
        if state == .streaming {
            do {
                let text = try await engine.finishStream(id: id)
                state = .failed
                return Self.result(text, transcribe: clock.now - start, fallback: false)
            } catch {
                fail("finish", error)
            }
        }
        let speech = await voice.speech(in: audio) ?? []
        let text = speech.isEmpty ? "" : try await engine.transcribe(speech)
        return Self.result(text, transcribe: clock.now - start, fallback: true)
    }

    func cancel() async {
        if state == .streaming { await engine.cancelStream(id: id) }
        state = .failed
    }

    private func feedRest() async {
        guard fed < audio.count else { return }
        let chunk = Array(audio[fed...])
        fed = audio.count
        do {
            if let text = try await engine.feedStream(id: id, chunk), text != lastText {
                lastText = text
                onText?(text)
            }
        } catch {
            fail("feed", error)
        }
    }

    private func fail(_ step: String, _ error: Error) {
        Log.app.error("Live stream \(step, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        state = .failed
    }

    private static func result(_ text: String, transcribe: Duration, fallback: Bool) -> LiveTranscriber.Result {
        LiveTranscriber.Result(
            text: text, piecesWhileTalking: 0, tailSeconds: 0, detectAfterRelease: .zero,
            waitForPieces: .zero, transcribeTail: transcribe, usedFallback: fallback, streamed: !fallback
        )
    }
}
