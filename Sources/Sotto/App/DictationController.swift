import AppKit
import Observation
import os
import SottoCore

/// Runs the pipeline: hotkey → mic → live voice detection and transcription →
/// cleanup → insert. All decisions come from `DictationMachine`; this class
/// only performs its effects and feeds results back.
@Observable @MainActor
final class DictationController {
    enum Status: Equatable {
        case starting
        case downloading(Double)
        case needsSetup
        case ready
        case listening
        case failed(String)
    }

    struct LastDictation {
        let text: String
        let appName: String?
        let duration: TimeInterval
        let at: Date
        let releaseToPasteMs: Int?
        let breakdown: String
    }

    private(set) var status: Status = .starting
    private(set) var isPreparing = false
    private(set) var modelReady = false
    private(set) var last: LastDictation?
    private(set) var isPaused = false {
        didSet { onChange?() }
    }
    @ObservationIgnored private var resumeTask: Task<Void, Never>?

    /// Turns dictation off, for `minutes` or until `resume()`.
    func pause(minutes: Int?) {
        resumeTask?.cancel()
        isPaused = true
        guard let minutes else { return }
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            self?.isPaused = false
        }
    }

    func resume() {
        resumeTask?.cancel()
        isPaused = false
    }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored let store: SettingsStore
    @ObservationIgnored private var machine = DictationMachine()
    @ObservationIgnored private let hotkey = HotkeyMonitor()
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let engine = ParakeetEngine()
    @ObservationIgnored private let voice = VoiceDetector()
    @ObservationIgnored private let inserter = TextInserter()
    @ObservationIgnored private let pill = PillController()

    @ObservationIgnored private var micReady = false
    @ObservationIgnored private var breakdown = ""
    @ObservationIgnored private var recordingStarted = Date()
    @ObservationIgnored private var recordedSeconds: TimeInterval = 0
    /// Uptime of the key event that ended the recording.
    @ObservationIgnored private var stoppedAt: TimeInterval = 0
    @ObservationIgnored private var lastKeyEventAt: TimeInterval = 0
    @ObservationIgnored private var unloadTask: Task<Void, Never>?
    @ObservationIgnored private var setupRetry: Task<Void, Never>?
    @ObservationIgnored private var signpostState: OSSignpostIntervalState?
    /// The dictation being transcribed while the user talks, and the
    /// in-order stream of audio that feeds it.
    @ObservationIgnored private var live: LiveTranscriber?
    @ObservationIgnored private var liveInput: AsyncStream<[Float]>.Continuation?
    @ObservationIgnored private var liveFeed: Task<Void, Never>?

    init(store: SettingsStore) {
        self.store = store
    }

    private var settings: SottoSettings { store.settings }

    var isModelDownloaded: Bool { engine.isDownloaded }
    var modelDirectory: URL { engine.directory }
    var hotkeyRunning: Bool { hotkey.isRunning }

    var statusText: String {
        if isPaused { return "Paused. Dictation is off." }
        return switch status {
        case .starting: "Starting…"
        case .downloading(let fraction): "Downloading speech model… \(Int(fraction * 100))%"
        case .needsSetup: "Needs permissions to work"
        case .ready where isPreparing: "Preparing the speech model…"
        case .ready: "Ready. Hold \(settings.dictationKey.title) to dictate."
        case .listening: "Listening…"
        case .failed(let message): message
        }
    }

    func start() {
        hotkey.key = settings.dictationKey
        hotkey.onSignal = { [weak self] signal, time in self?.handle(signal, at: time) }
        pill.position = settings.pillPosition
        pill.keySymbol = settings.dictationKey.symbol
        store.onChange = { [weak self] settings in self?.apply(settings) }
        retrySetup()
        Task { await Permission.promptMissing() }
        Task {
            await downloadModelsIfNeeded()
            await prepareModel()
        }
    }

    private func apply(_ settings: SottoSettings) {
        hotkey.key = settings.dictationKey
        pill.position = settings.pillPosition
        pill.keySymbol = settings.dictationKey.symbol
        if machine.phase == .idle, modelReady { scheduleUnload() }
        onChange?()
    }

    /// Starts the hotkey once permissions allow it. While anything is missing
    /// it checks again every 2 seconds; once everything works, nothing runs.
    func retrySetup() {
        setupRetry?.cancel()
        setupRetry = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                if self.hotkey.start(), Permission.missing.isEmpty {
                    if case .downloading = self.status {} else { self.setStatus(.ready) }
                    return
                }
                self.setStatus(.needsSetup)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func forgetLastTranscript() {
        last = nil
        onChange?()
    }

    private func downloadModelsIfNeeded() async {
        guard !engine.isDownloaded else { return }
        setStatus(.downloading(0))
        do {
            try await engine.download { [weak self] fraction in
                Task { @MainActor in self?.setStatus(.downloading(fraction)) }
            }
            // Fetches the voice-detection model, then frees it until needed.
            try await voice.load()
            await voice.unload()
            setStatus(Permission.missing.isEmpty && hotkey.isRunning ? .ready : .needsSetup)
        } catch {
            Log.app.error("Model download failed: \(error.localizedDescription, privacy: .public)")
            setStatus(.failed("Couldn't download the speech model. Check your connection and relaunch."))
        }
    }

    /// Loads the model once at launch. The first load after installing
    /// compiles it for this Mac's Neural Engine, which took 12.8 s on an M5;
    /// doing it now keeps that wait out of the first dictation. The idle
    /// timer then frees it as usual, and later loads hit CoreML's cache.
    private func prepareModel() async {
        guard engine.isDownloaded else { return }
        isPreparing = true
        onChange?()
        let clock = ContinuousClock()
        let start = clock.now
        try? await voice.load()
        do {
            try await engine.load()
            modelReady = true
        } catch {
            Log.app.error("Model load failed: \(error.localizedDescription, privacy: .public)")
        }
        Log.app.info("Model prepared in \(Self.milliseconds(clock.now - start)) ms")
        isPreparing = false
        onChange?()
        scheduleUnload()
    }

    private func setStatus(_ status: Status) {
        guard self.status != status else { return }
        self.status = status
        onChange?()
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int((Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15).rounded())
    }

    // MARK: - Events

    private func handle(_ signal: HotkeyMonitor.Signal, at time: TimeInterval) {
        lastKeyEventAt = time
        switch signal {
        case .down:
            guard !isPaused || machine.currentSession != nil else { return }
            machine.latchOnTap = settings.tapToKeepListening
            send(.hotkeyDown(at: time))
        case .up: send(.hotkeyUp(at: time))
        case .chord: send(.chord)
        case .escape: if machine.currentSession != nil { send(.cancel) }
        }
    }

    private func send(_ event: DictationMachine.Event) {
        let effects = machine.handle(event)
        for effect in effects { perform(effect) }
        refreshPill()
    }

    private func perform(_ effect: DictationMachine.Effect) {
        switch effect {
        case .startCapture(let session):
            startCapture(session)
        case .stopCaptureAndTranscribe(let session):
            stopAndTranscribe(session)
        case .discardCapture:
            _ = recorder.stop()
            liveInput?.finish()
            liveFeed?.cancel()
            if let live { Task { await live.cancel() } }
            (live, liveInput, liveFeed) = (nil, nil, nil)
            endSignpost()
            pill.hide()
            setStatus(.ready)
        case .insert(let text, let session):
            insert(text, session: session)
        case .reportEmpty:
            endSignpost()
            pill.flash("Didn't catch that", isError: false)
            scheduleUnload()
        case .reportFailure(let message, _):
            endSignpost()
            pill.flash(message, isError: true)
            setStatus(.ready)
        }
    }

    private func startCapture(_ session: Int) {
        unloadTask?.cancel()
        inserter.prepare()
        micReady = false
        recordingStarted = Date()
        signpostState = Log.signposter.beginInterval("dictation", id: Log.signposter.makeSignpostID())

        // Load while the user talks, so the model is ready when they let go.
        // If it's already loaded, wake the Neural Engine instead; after idle,
        // transcription runs about 3x slower (docs/measurements.md).
        Task { [engine, voice] in
            let wasLoaded = await engine.isLoaded
            try? await voice.load()
            await voice.warmUp()
            do {
                try await engine.load()
                self.modelReady = true
                self.refreshPill()
                if wasLoaded { await engine.warmUp() }
            } catch {
                Log.app.error("Model load failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        let live = LiveTranscriber(engine: engine, voice: voice)
        let (stream, input) = AsyncStream.makeStream(of: [Float].self)
        self.live = live
        liveInput = input
        liveFeed = Task {
            for await chunk in stream { await live.append(chunk) }
        }

        do {
            try recorder.start(
                onFirstAudio: { [weak self] in
                    Task { @MainActor in self?.micBecameReady(session) }
                },
                onLevel: { [weak self] level in
                    Task { @MainActor in self?.pill.push(level: level) }
                },
                onAudio: { chunk in input.yield(chunk) },
                deviceUID: settings.microphoneUID
            )
            setStatus(.listening)
        } catch {
            send(.failed(session: session, message: "Microphone unavailable"))
        }
    }

    private func micBecameReady(_ session: Int) {
        guard machine.currentSession == session else { return }
        micReady = true
        if settings.playSounds { Sounds.playStart() }
        Log.signposter.emitEvent("mic ready")
        refreshPill()
    }

    private func stopAndTranscribe(_ session: Int) {
        stoppedAt = lastKeyEventAt
        recordedSeconds = Date().timeIntervalSince(recordingStarted)
        Log.signposter.emitEvent("released")
        let clock = ContinuousClock()
        let stopStart = clock.now
        let samples = recorder.stop()
        let micCloseTime = clock.now - stopStart
        if settings.playSounds { Sounds.playStop() }
        setStatus(.ready)
        guard let live, let liveFeed else {
            send(.failed(session: session, message: "Couldn't transcribe"))
            return
        }
        liveInput?.finish()
        (self.live, liveInput, self.liveFeed) = (nil, nil, nil)
        let cleanup = (removeFillers: settings.removeFillerWords, words: settings.customWords)
        Task {
            let interval = Log.signposter.beginInterval("transcribe")
            defer { Log.signposter.endInterval("transcribe", interval) }
            let waitedToStart = ProcessInfo.processInfo.systemUptime - self.stoppedAt
            // Let the stream deliver what it already has before finishing.
            await liveFeed.value
            do {
                let result = try await live.finish(fullAudio: samples)
                self.breakdown = String(
                    format: "%.1f s audio · %d pieces done while talking · %.1f s tail · key-up to work %d ms (mic close %d) · detection %d ms · waiting for pieces %d ms · tail transcription %d ms%@",
                    Double(samples.count) / 16_000, result.piecesWhileTalking, result.tailSeconds,
                    Int((waitedToStart * 1000).rounded()), Self.milliseconds(micCloseTime),
                    Self.milliseconds(result.detectAfterRelease), Self.milliseconds(result.waitForPieces),
                    Self.milliseconds(result.transcribeTail), result.usedFallback ? " · whole-recording fallback" : ""
                )
                let text = TextCleanup.clean(result.text, removeFillers: cleanup.removeFillers, customWords: cleanup.words)
                self.send(.transcribed(session: session, text: text))
            } catch {
                Log.app.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                self.send(.failed(session: session, message: "Couldn't transcribe"))
            }
        }
    }

    private func insert(_ text: String, session: Int) {
        let releasedAt = stoppedAt
        let duration = recordedSeconds
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        Task {
            let insertStart = ProcessInfo.processInfo.systemUptime
            // A trailing space keeps back-to-back dictations from running together.
            let outcome = await inserter.insert(text + " ")
            endSignpost()
            var pasteMs: Int?
            switch outcome {
            case .inserted(let chordAt, let readAt):
                let toPaste = Int(((chordAt - releasedAt) * 1000).rounded())
                let toRead = Int(((readAt - releasedAt) * 1000).rounded())
                let pasteStep = Int(((chordAt - insertStart) * 1000).rounded())
                breakdown += " · paste \(pasteStep) ms"
                pasteMs = toPaste
                Log.app.info("release→paste \(toPaste) ms, release→read \(toRead) ms · \(self.breakdown, privacy: .public)")
                pill.hide()
            case .notRead:
                pill.flash("Couldn't paste. Copy it from the menu.", isError: true)
            case .failed:
                pill.flash("Couldn't paste. Check Accessibility.", isError: true)
            }
            last = LastDictation(
                text: text, appName: pasteMs == nil ? nil : appName, duration: duration,
                at: Date(), releaseToPasteMs: pasteMs, breakdown: breakdown
            )
            onChange?()
            scheduleUnload()
        }
    }

    private func endSignpost() {
        if let signpostState {
            Log.signposter.endInterval("dictation", signpostState)
            self.signpostState = nil
        }
    }

    /// One timer, re-armed after each dictation, that frees the model's
    /// memory after the idle time set in Settings.
    private func scheduleUnload() {
        unloadTask?.cancel()
        let minutes = settings.unloadAfterMinutes
        guard minutes > 0 else { return }
        unloadTask = Task { [engine, voice] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            await engine.unload()
            await voice.unload()
            self.modelReady = false
            self.onChange?()
            Log.app.info("Model unloaded after idle")
        }
    }

    private func refreshPill() {
        switch machine.phase {
        case .idle:
            // Insertion hides the pill itself once the text has landed.
            break
        case .recording(_, _, let latched):
            guard settings.showPill else { return }
            pill.show(micReady ? .listening(latched: latched, since: recordingStarted) : .gettingReady)
        case .transcribing:
            guard settings.showPill else { return }
            pill.show(modelReady ? .transcribing : .loadingModel)
        }
    }
}
