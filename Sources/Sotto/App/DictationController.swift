import AppKit
import os
import SottoCore

/// Runs the pipeline: hotkey → mic → voice detection → Parakeet → cleanup →
/// insert. All decisions come from `DictationMachine`; this class only
/// performs its effects and feeds results back.
@MainActor
final class DictationController {
    enum Status: Equatable {
        case starting
        case downloading(Double)
        case needsSetup
        case ready
        case listening
        case failed(String)
    }

    private(set) var status: Status = .starting
    private(set) var lastTranscript: String?
    private(set) var lastTimingText: String?
    var onChange: (() -> Void)?

    private var machine = DictationMachine()
    private let hotkey = HotkeyMonitor()
    private let recorder = AudioRecorder()
    private let engine = ParakeetEngine()
    private let voice = VoiceDetector()
    private let inserter = TextInserter()
    private let pill = PillController()

    private var modelReady = false
    private var isPreparing = false
    private var micReady = false
    /// Per-step timings of the dictation in flight, for the menu and the log.
    private var breakdown = ""
    private var recordingStarted = Date()
    /// Uptime of the key event that ended the recording.
    private var stoppedAt: TimeInterval = 0
    private var lastKeyEventAt: TimeInterval = 0
    private var unloadTask: Task<Void, Never>?
    private var setupRetry: Task<Void, Never>?
    private var signpostState: OSSignpostIntervalState?
    private static let unloadAfter: Duration = .seconds(5 * 60)

    var statusText: String {
        switch status {
        case .starting: "Starting…"
        case .downloading(let fraction): "Downloading speech model… \(Int(fraction * 100))%"
        case .needsSetup: "Needs permissions to work"
        case .ready where isPreparing: "Preparing the speech model…"
        case .ready: "Ready. Hold Right ⌥ to dictate."
        case .listening: "Listening…"
        case .failed(let message): message
        }
    }

    func start() {
        hotkey.onSignal = { [weak self] signal, time in self?.handle(signal, at: time) }
        retrySetup()
        Task { await Permission.promptMissing() }
        Task {
            await downloadModelsIfNeeded()
            await prepareModel()
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

    private static func milliseconds(_ duration: Duration) -> Int {
        Int((Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15).rounded())
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

    private func setStatus(_ status: Status) {
        guard self.status != status else { return }
        self.status = status
        onChange?()
    }

    // MARK: - Events

    private func handle(_ signal: HotkeyMonitor.Signal, at time: TimeInterval) {
        lastKeyEventAt = time
        switch signal {
        case .down: send(.hotkeyDown(at: time))
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
            endSignpost()
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
        // If it's already loaded, wake the Neural Engine instead: live
        // transcription measured 88 ms against 45 ms when the engine was busy.
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

        do {
            try recorder.start(
                onFirstAudio: { [weak self] in
                    Task { @MainActor in self?.micBecameReady(session) }
                },
                onLevel: { [weak self] level in
                    Task { @MainActor in self?.pill.push(level: level) }
                }
            )
            setStatus(.listening)
        } catch {
            send(.failed(session: session, message: "Microphone unavailable"))
        }
    }

    private func micBecameReady(_ session: Int) {
        guard machine.currentSession == session else { return }
        micReady = true
        Log.signposter.emitEvent("mic ready")
        refreshPill()
    }

    private func stopAndTranscribe(_ session: Int) {
        stoppedAt = lastKeyEventAt
        Log.signposter.emitEvent("released")
        let clock = ContinuousClock()
        let stopStart = clock.now
        let samples = recorder.stop()
        let micCloseTime = clock.now - stopStart
        setStatus(.ready)
        Task { [engine, voice] in
            let interval = Log.signposter.beginInterval("transcribe")
            defer { Log.signposter.endInterval("transcribe", interval) }
            let start = clock.now
            let waitedToStart = ProcessInfo.processInfo.systemUptime - self.stoppedAt
            let detected = await voice.speech(in: samples)
            let detectTime = clock.now - start
            guard let speech = detected else {
                self.send(.transcribed(session: session, text: ""))
                return
            }
            do {
                let wasLoaded = await engine.isLoaded
                let transcribeStart = clock.now
                let raw = try await engine.transcribe(speech)
                let transcribeTime = clock.now - transcribeStart
                self.breakdown = String(
                    format: "%.1f s audio · key-up to work %d ms (mic close %d) · voice detection %d ms · %@ %d ms",
                    Double(samples.count) / 16_000,
                    Int((waitedToStart * 1000).rounded()), Self.milliseconds(micCloseTime),
                    Self.milliseconds(detectTime),
                    wasLoaded ? "transcription" : "load + transcription", Self.milliseconds(transcribeTime)
                )
                self.send(.transcribed(session: session, text: TextCleanup.clean(raw)))
            } catch {
                Log.app.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                self.send(.failed(session: session, message: "Couldn't transcribe"))
            }
        }
    }

    private func insert(_ text: String, session: Int) {
        lastTranscript = text
        let releasedAt = stoppedAt
        Task {
            let insertStart = ProcessInfo.processInfo.systemUptime
            // A trailing space keeps back-to-back dictations from running together.
            let outcome = await inserter.insert(text + " ")
            endSignpost()
            switch outcome {
            case .inserted(let chordAt, let readAt):
                let toPaste = Int(((chordAt - releasedAt) * 1000).rounded())
                let toRead = Int(((readAt - releasedAt) * 1000).rounded())
                let pasteStep = Int(((chordAt - insertStart) * 1000).rounded())
                breakdown += " · paste \(pasteStep) ms"
                lastTimingText = "Pasted \(toPaste) ms after release · \(breakdown)"
                Log.app.info("release→paste \(toPaste) ms, release→read \(toRead) ms · \(self.breakdown, privacy: .public)")
                if !pill.isShowingMessage { pill.hide() }
            case .notRead:
                lastTimingText = nil
                pill.flash("Couldn't paste. Copy it from the menu.", isError: true)
            case .failed:
                lastTimingText = nil
                pill.flash("Couldn't paste. Check Accessibility.", isError: true)
            }
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

    /// One timer, re-armed after each dictation. It frees the model's memory
    /// after five idle minutes.
    private func scheduleUnload() {
        unloadTask?.cancel()
        unloadTask = Task { [engine, voice] in
            try? await Task.sleep(for: Self.unloadAfter)
            guard !Task.isCancelled else { return }
            await engine.unload()
            await voice.unload()
            self.modelReady = false
            Log.app.info("Model unloaded after idle")
        }
    }

    private func refreshPill() {
        switch machine.phase {
        case .idle:
            // Insertion hides the pill itself once the text has landed.
            break
        case .recording(_, _, let latched):
            pill.show(micReady ? .listening(latched: latched, since: recordingStarted) : .gettingReady)
        case .transcribing:
            pill.show(modelReady ? .transcribing : .loadingModel)
        }
    }
}
