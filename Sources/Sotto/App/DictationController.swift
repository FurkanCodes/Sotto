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
    @ObservationIgnored let history: HistoryStore
    @ObservationIgnored private var machine = DictationMachine()
    @ObservationIgnored private let hotkey = HotkeyMonitor()
    @ObservationIgnored private let recorder = AudioRecorder()
    /// Parakeet v3 on the Neural Engine, built in and used by default.
    @ObservationIgnored private let builtIn = ParakeetEngine()
    /// Catalog models, run by the SottoEngine helper process.
    @ObservationIgnored private let helper = HelperEngine()
    @ObservationIgnored let models: ModelStore
    @ObservationIgnored private var activeModelID: String?
    @ObservationIgnored private let voice = VoiceDetector()
    @ObservationIgnored private let inserter = TextInserter()
    @ObservationIgnored private let pill = PillController()
    @ObservationIgnored private let fieldWatcher = FieldWatcher()
    @ObservationIgnored private let suggestion = SuggestionPanel()

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
    @ObservationIgnored private var live: (any LiveTranscribing)?
    @ObservationIgnored private var liveInput: AsyncStream<[Float]>.Continuation?
    @ObservationIgnored private var liveFeed: Task<Void, Never>?
    /// What happened in the dictation in flight, for messages and sending.
    @ObservationIgnored private var recordingPeak: Float = 0
    @ObservationIgnored private var liveText = ""
    @ObservationIgnored private var pressReturnAfterInsert = false
    @ObservationIgnored private var appendSpaceAfterInsert = true

    init(store: SettingsStore, history: HistoryStore, models: ModelStore) {
        self.store = store
        self.history = history
        self.models = models
    }

    /// The catalog model in use, if one is chosen and downloaded; nil means
    /// the built-in Parakeet v3.
    var catalogModel: CatalogModel? {
        guard let id = settings.modelID, let model = ModelCatalog.model(id: id), models.isInstalled(model) else { return nil }
        return model
    }

    private var engine: any SpeechEngine {
        catalogModel == nil ? builtIn : helper
    }

    /// Points the helper at the chosen model, language and custom words.
    private func configureHelper() async {
        guard let model = catalogModel, let path = models.path(for: model) else { return }
        await helper.configure(
            modelPath: path.path,
            language: model.isMultilingual ? settings.modelLanguage.flatMap(model.languageTag) : nil,
            vocabulary: settings.customWords
        )
    }

    /// The mic in use, for messages: "MacBook Pro Microphone".
    private var microphoneName: String {
        AudioDevices.inputs().first { $0.id == settings.microphoneUID }?.name
            ?? AudioDevices.defaultInputName() ?? "the microphone"
    }

    private var settings: SottoSettings { store.settings }

    var isModelDownloaded: Bool { builtIn.isDownloaded }
    var modelDirectory: URL { builtIn.directory }
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
        fieldWatcher.onLearned = { [weak self] word in self?.offerToLearn(word) }
        hotkey.key = settings.dictationKey
        hotkey.mouseButton = settings.mouseButton
        history.prune(retentionDays: settings.historyRetentionDays)
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
        Task { await configureHelper() }
        if catalogModel?.id != activeModelID, machine.phase == .idle {
            // A different model: free the old one and prepare the new one.
            activeModelID = catalogModel?.id
            modelReady = false
            Task { [builtIn, helper] in
                await builtIn.unload()
                await helper.unload()
                await self.prepareModel()
            }
        }
        hotkey.key = settings.dictationKey
        hotkey.mouseButton = settings.mouseButton
        history.prune(retentionDays: settings.historyRetentionDays)
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

    /// Transcribes an audio or video file with the same models and cleanup
    /// as dictation (but no snippets or sending).
    func transcribeFile(_ url: URL) async throws -> String {
        let samples = try await MediaReader.samples(from: url)
        try await voice.load()
        await configureHelper()
        let engine = self.engine
        try await engine.load()
        modelReady = true
        defer { scheduleUnload() }
        guard let speech = await voice.speech(in: samples), !speech.isEmpty else { return "" }
        let raw = try await engine.transcribe(speech)
        let cleaned = TextCleanup.clean(raw, removeFillers: settings.removeFillerWords, customWords: settings.customWords)
        return TextRules.applyReplacements(cleaned, settings.replacements)
    }

    func forgetLastTranscript() {
        last = nil
        onChange?()
    }

    private func downloadModelsIfNeeded() async {
        guard !builtIn.isDownloaded else { return }
        setStatus(.downloading(0))
        do {
            try await builtIn.download { [weak self] fraction in
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
        guard builtIn.isDownloaded else { return }
        await configureHelper()
        activeModelID = catalogModel?.id
        let engine = self.engine
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
            if machine.currentSession == nil {
                guard !isPaused else { return }
                if let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                   settings.skipApps.contains(where: { $0.bundleID == app }) { return }
            }
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
            SystemVolume.restore()
            setStatus(.ready)
        case .insert(let text, let session):
            insert(text, session: session)
        case .reportEmpty:
            endSignpost()
            if pressReturnAfterInsert {
                // Just "send it": press Return for text typed earlier.
                inserter.pressReturn(withCommand: autoSendRule()?.withCommand ?? false)
                pill.hide()
            } else if recordedSeconds > 1, recordingPeak < 0.0005 {
                pill.flash("No sound from \(microphoneName). Is it muted?", isError: true)
            } else {
                pill.flash("Didn't catch that", isError: false)
            }
            scheduleUnload()
        case .reportFailure(let message, _):
            endSignpost()
            pill.flash(message, isError: true)
            setStatus(.ready)
        }
    }

    private func startCapture(_ session: Int) {
        if !Permission.microphone.isGranted {
            send(.failed(session: session, message: "Sotto can't use the microphone. Allow it from the menu."))
            return
        }
        if !builtIn.isDownloaded {
            send(.failed(session: session, message: "The speech model isn't downloaded yet."))
            return
        }
        unloadTask?.cancel()
        fieldWatcher.stop()
        suggestion.hide()
        inserter.prepare()
        micReady = false
        recordingPeak = 0
        liveText = ""
        pressReturnAfterInsert = false
        recordingStarted = Date()
        signpostState = Log.signposter.beginInterval("dictation", id: Log.signposter.makeSignpostID())

        // Load while the user talks, so the model is ready when they let go.
        // If it's already loaded, wake the Neural Engine instead; after idle,
        // transcription runs about 3x slower (docs/measurements.md).
        let engine = self.engine
        Task { [voice] in
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

        let live: any LiveTranscribing
        if catalogModel?.streams == true {
            live = StreamingTranscriber(engine: helper, voice: voice, id: session) { [weak self] text in
                Task { @MainActor in self?.showLiveText(text, session: session) }
            }
        } else {
            live = LiveTranscriber(engine: engine, voice: voice) { [weak self] text in
                Task { @MainActor in self?.addLiveText(text, session: session) }
            }
        }
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
                    Task { @MainActor in
                        self?.pill.push(level: level)
                        if let self, level > self.recordingPeak { self.recordingPeak = level }
                    }
                },
                onAudio: { chunk in input.yield(chunk) },
                deviceUID: settings.microphoneUID
            )
            setStatus(.listening)
        } catch AudioRecorder.RecorderError.noInputDevice {
            send(.failed(session: session, message: "No microphone found. Connect one or pick another in the menu."))
        } catch {
            send(.failed(session: session, message: "Couldn't start \(microphoneName)."))
        }
    }

    private func micBecameReady(_ session: Int) {
        guard machine.currentSession == session else { return }
        micReady = true
        if settings.playSounds { Sounds.playStart() }
        if settings.lowerOtherAudio {
            // After the start sound, so the sound itself isn't turned down.
            let delay = settings.playSounds ? 200 : 0
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(delay))
                guard let self, self.machine.currentSession == session else { return }
                SystemVolume.lower()
            }
        }
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
        SystemVolume.restore()
        if settings.playSounds { Sounds.playStop() }
        setStatus(.ready)
        guard let live, let liveFeed else {
            send(.failed(session: session, message: "Couldn't transcribe"))
            return
        }
        liveInput?.finish()
        (self.live, liveInput, self.liveFeed) = (nil, nil, nil)
        let cleanup = (removeFillers: settings.removeFillerWords, words: settings.customWords, corrections: settings.fixSelfCorrections)
        let rules = (replacements: settings.replacements, snippets: settings.snippets, sayToSend: settings.sayToSend)
        // The style follows the app in front when the key goes up.
        let style = settings.matchStyleToApp
            ? Styles.style(forBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, rules: settings.styleRules)
            : .standard
        appendSpaceAfterInsert = style.appendsSpace
        // Read now, before the paste replaces the clipboard.
        let clipboard = rules.snippets.contains { $0.text.contains("{clipboard}") }
            ? NSPasteboard.general.string(forType: .string) : nil
        Task {
            let interval = Log.signposter.beginInterval("transcribe")
            defer { Log.signposter.endInterval("transcribe", interval) }
            let waitedToStart = ProcessInfo.processInfo.systemUptime - self.stoppedAt
            // Let the stream deliver what it already has before finishing.
            await liveFeed.value
            do {
                let result = try await live.finish(fullAudio: samples)
                if result.streamed {
                    self.breakdown = String(
                        format: "%.1f s audio · streamed · key-up to work %d ms (mic close %d) · finishing the stream %d ms",
                        Double(samples.count) / 16_000, Int((waitedToStart * 1000).rounded()),
                        Self.milliseconds(micCloseTime), Self.milliseconds(result.transcribeTail)
                    )
                } else {
                    self.breakdown = String(
                        format: "%.1f s audio · %d pieces done while talking · %.1f s tail · key-up to work %d ms (mic close %d) · detection %d ms · waiting for pieces %d ms · tail transcription %d ms%@",
                        Double(samples.count) / 16_000, result.piecesWhileTalking, result.tailSeconds,
                        Int((waitedToStart * 1000).rounded()), Self.milliseconds(micCloseTime),
                        Self.milliseconds(result.detectAfterRelease), Self.milliseconds(result.waitForPieces),
                        Self.milliseconds(result.transcribeTail), result.usedFallback ? " · whole-recording fallback" : ""
                    )
                }
                let cleaned = TextCleanup.clean(result.text, removeFillers: cleanup.removeFillers, customWords: cleanup.words)
                let corrected = cleanup.corrections ? SelfCorrection.apply(cleaned) : cleaned
                // Style first, so replacements and snippets come out exactly as written.
                let styled = Styles.apply(corrected, style: style, keepCapitalized: cleanup.words)
                let final = TextRules.apply(
                    styled, replacements: rules.replacements, snippets: rules.snippets,
                    sayToSend: rules.sayToSend, clipboard: clipboard
                )
                self.pressReturnAfterInsert = final.send
                self.send(.transcribed(session: session, text: final.text))
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
            // In hands-free mode the stopping press is still down; wait for it.
            await hotkey.waitForRelease()
            let insertStart = ProcessInfo.processInfo.systemUptime
            // A trailing space keeps back-to-back dictations from running
            // together; code editors and terminals don't get one.
            let outcome = await inserter.insert(text + (appendSpaceAfterInsert ? " " : ""))
            endSignpost()
            var pasteMs: Int?
            let target = appName ?? "unknown app"
            switch outcome {
            case .inserted(let method, let chordAt, let landedAt):
                if pressReturnAfterInsert || autoSendRule() != nil {
                    // A short pause, so the app has the text before Return arrives.
                    try? await Task.sleep(for: .milliseconds(50))
                    inserter.pressReturn(withCommand: autoSendRule()?.withCommand ?? false)
                }
                let toPaste = Int(((chordAt - releasedAt) * 1000).rounded())
                let toLanded = Int(((landedAt - releasedAt) * 1000).rounded())
                let pasteStep = Int(((chordAt - insertStart) * 1000).rounded())
                breakdown += " · paste \(pasteStep) ms" + (method == .paste ? "" : " · inserted by \(method.rawValue)")
                pasteMs = toPaste
                // Notice level, so macOS keeps it long enough to diagnose problems.
                Log.app.notice("insert \(method.rawValue, privacy: .public) into \(target, privacy: .public): release→paste \(toPaste) ms, release→landed \(toLanded) ms · \(self.breakdown, privacy: .public)")
                pill.hide()
                if settings.learnFromCorrections {
                    // Give the app a moment to show the pasted text, then watch for fixes.
                    try? await Task.sleep(for: .milliseconds(300))
                    if machine.phase == .idle {
                        fieldWatcher.watch(inserted: text, knownWords: settings.customWords)
                    }
                }
            case .leftOnClipboard:
                Log.app.notice("insert failed in \(target, privacy: .public): no text field took it; left on clipboard")
                pill.flash("Copied. Press ⌘V to paste.", isError: true)
            case .failed:
                Log.app.error("insert failed in \(target, privacy: .public): couldn't post keystrokes")
                pill.flash("Couldn't paste. Check Accessibility.", isError: true)
            }
            history.add(
                HistoryEntry(text: text, date: Date(), appName: pasteMs == nil ? nil : appName, seconds: duration),
                retentionDays: settings.historyRetentionDays
            )
            last = LastDictation(
                text: text, appName: pasteMs == nil ? nil : appName, duration: duration,
                at: Date(), releaseToPasteMs: pasteMs, breakdown: breakdown
            )
            onChange?()
            scheduleUnload()
        }
    }

    private func offerToLearn(_ word: String) {
        guard machine.phase == .idle else { return }
        Log.app.notice("Offering a learned dictionary word")
        suggestion.offer(word, position: settings.pillPosition) { [weak self] in
            guard let self, !self.store.settings.customWords.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return }
            self.store.settings.customWords.append(word)
        }
    }

    /// The auto-send rule for the app in front, if any.
    private func autoSendRule() -> AutoSendRule? {
        guard let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
        return settings.autoSendApps.first { $0.app.bundleID == app }
    }

    private func addLiveText(_ text: String, session: Int) {
        guard machine.currentSession == session, settings.showLiveText else { return }
        let piece = TextCleanup.clean(text, removeFillers: settings.removeFillerWords, customWords: settings.customWords)
        liveText = liveText.isEmpty ? piece : liveText + " " + piece
        pill.setLiveText(liveText)
    }

    /// A stream's whole text so far, which replaces the caption.
    private func showLiveText(_ text: String, session: Int) {
        guard machine.currentSession == session, settings.showLiveText else { return }
        liveText = TextCleanup.clean(text, removeFillers: settings.removeFillerWords, customWords: settings.customWords)
        pill.setLiveText(liveText)
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
        unloadTask = Task { [builtIn, helper, voice] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            await builtIn.unload()
            await helper.unload()
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
