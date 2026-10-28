import FluidAudio

/// Transcribes one dictation in pieces while the user is still talking.
///
/// Audio streams in through `append`, and Silero scores each 256 ms window as
/// it arrives. A window scoring under `pauseThreshold` is a pause. Once a
/// piece holds at least `minPiece` of audio, it is cut in the middle of the
/// next pause and transcribed in the background. At release, `finish` only
/// has the last piece left. This keeps the time after release flat as
/// dictations get longer, and keeps the hardware busy, which avoids the
/// after-idle slowdown measured in docs/measurements.md.
///
/// Silero's own end-of-speech event waits for 0.75 s of silence, which
/// ordinary sentence pauses (~600 ms: two or three windows scoring 0.1–0.4)
/// rarely reach, so the scores are used directly.
///
/// If voice detection isn't loaded or fails, `finish` falls back to
/// transcribing the whole recording at once.
actor LiveTranscriber {
    struct Result {
        let text: String
        /// Pieces transcribed while the user was talking.
        let piecesWhileTalking: Int
        let tailSeconds: Double
        /// Time spent after release: detection on the last windows, waiting
        /// for a piece still in progress, and transcribing the tail.
        let detectAfterRelease: Duration
        let waitForPieces: Duration
        let transcribeTail: Duration
        let usedFallback: Bool
    }

    private static let window = VoiceDetector.windowSize
    private static let pauseThreshold: Float = 0.5
    /// Pieces are only ever cut at real pauses. Forcing a cut into continuous
    /// speech split words across pieces ("the settings file. File gets read"),
    /// so speech that never pauses stays in one piece.
    private static let minPiece = 4 * VoiceDetector.sampleRate
    /// Silence kept before and after speech, like Handy's 450 ms (audio_toolkit/vad).
    private static let padding = Int(0.45 * Double(VoiceDetector.sampleRate))

    private let engine: ParakeetEngine
    private let voice: VoiceDetector
    /// Called with each piece's text as it finishes, in order.
    private let onPiece: (@Sendable (String) -> Void)?
    private var audio: [Float] = []
    private var analyzed = 0
    private var vadState = VadStreamState()
    private var detectionFailed = false
    /// Where the piece being built starts.
    private var pieceStart = 0
    private var pieceHasSpeech = false
    /// End of the last window that scored as speech.
    private var lastSpeechEnd: Int?
    private var pieces: [Task<String, Error>] = []

    init(engine: ParakeetEngine, voice: VoiceDetector, onPiece: (@Sendable (String) -> Void)? = nil) {
        self.engine = engine
        self.voice = voice
        self.onPiece = onPiece
    }

    /// Called in order with each chunk of 16 kHz audio while recording.
    func append(_ samples: [Float]) async {
        audio.append(contentsOf: samples)
        await analyzeFullWindows()
    }

    /// Transcribes what's left and returns the whole text. `fullAudio` is the
    /// complete recording; the stream can miss the last buffer.
    func finish(fullAudio: [Float]) async throws -> Result {
        let clock = ContinuousClock()
        if fullAudio.count > audio.count {
            audio = fullAudio
        }

        let detectStart = clock.now
        await analyzeFullWindows()
        if !detectionFailed, analyzed < audio.count {
            // The last partial window, padded with silence.
            var window = Array(audio[analyzed...])
            window += [Float](repeating: 0, count: Self.window - window.count)
            analyzed = audio.count
            await analyze(window, endingAt: audio.count)
        }
        let detectTime = clock.now - detectStart

        if detectionFailed {
            for piece in pieces { piece.cancel() }
            let start = clock.now
            let speech = await voice.speech(in: audio) ?? []
            let text = speech.isEmpty ? "" : try await engine.transcribe(speech)
            return Result(
                text: text, piecesWhileTalking: 0,
                tailSeconds: Double(audio.count) / Double(VoiceDetector.sampleRate),
                detectAfterRelease: .zero, waitForPieces: .zero, transcribeTail: clock.now - start, usedFallback: true
            )
        }

        let waitStart = clock.now
        var texts: [String] = []
        for piece in pieces {
            texts.append(try await piece.value)
        }
        let waitTime = clock.now - waitStart

        // The tail, without the silence after the last speech.
        var tail: [Float] = []
        if pieceHasSpeech, let lastSpeechEnd {
            let end = min(audio.count, lastSpeechEnd + Self.padding)
            if pieceStart < end { tail = Array(audio[pieceStart..<end]) }
        }
        let tailStart = clock.now
        if !tail.isEmpty {
            texts.append(try await engine.transcribe(tail))
        }
        let tailTime = clock.now - tailStart

        return Result(
            text: texts.filter { !$0.isEmpty }.joined(separator: " "),
            piecesWhileTalking: pieces.count,
            tailSeconds: Double(tail.count) / Double(VoiceDetector.sampleRate),
            detectAfterRelease: detectTime, waitForPieces: waitTime, transcribeTail: tailTime, usedFallback: false
        )
    }

    func cancel() {
        for piece in pieces { piece.cancel() }
        pieces = []
    }

    private func analyzeFullWindows() async {
        while !detectionFailed, audio.count - analyzed >= Self.window {
            let window = Array(audio[analyzed..<(analyzed + Self.window)])
            analyzed += Self.window
            await analyze(window, endingAt: analyzed)
        }
    }

    private func analyze(_ window: [Float], endingAt end: Int) async {
        let probability: Float
        do {
            guard let result = try await voice.stream(window, state: vadState) else {
                detectionFailed = true
                return
            }
            vadState = result.state
            probability = result.probability
        } catch {
            Log.app.error("Live voice detection failed: \(error.localizedDescription, privacy: .public)")
            detectionFailed = true
            return
        }

        if probability >= Self.pauseThreshold {
            pieceHasSpeech = true
            lastSpeechEnd = end
            return
        }
        guard pieceHasSpeech else {
            // No speech yet in this piece: drop the leading silence, keeping some padding.
            pieceStart = max(pieceStart, end - Self.padding)
            return
        }
        if end - pieceStart >= Self.minPiece {
            sendPiece(upTo: end - Self.window / 2)
        }
    }

    private func sendPiece(upTo cut: Int) {
        let piece = Array(audio[pieceStart..<cut])
        pieceStart = cut
        pieceHasSpeech = false
        let engine = self.engine
        let onPiece = self.onPiece
        let previous = pieces.last
        // One at a time, in order: the next piece waits for the previous one.
        pieces.append(Task {
            _ = try? await previous?.value
            let text = try await engine.transcribe(piece)
            onPiece?(text)
            return text
        })
    }
}
