// The SottoEngine XPC helper: runs transcribe.cpp models (Whisper,
// Parakeet GGUF, Nemotron, Canary and the rest of the catalog) outside the
// app process. Ported in spirit from Handy's engine_supervisor worker.
import CTranscribe
import Foundation
import SottoEngineProtocol

/// One model and one session, used from a single serial queue.
final class Engine: NSObject, SottoEngineXPC, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.furkan.sotto.engine")
    private var model: OpaquePointer?
    private var session: OpaquePointer?
    private var loadedPath: String?
    private var backendsReady = false
    /// The live stream in progress, if any.
    private var streamID: Int?

    func load(modelPath: String, reply: @escaping @Sendable (String?) -> Void) {
        queue.async { reply(self.loadOnQueue(modelPath, backend: TRANSCRIBE_BACKEND_AUTO)) }
    }

    func transcribe(samples: Data, language: String?, vocabulary: String, reply: @escaping @Sendable (String?, String?) -> Void) {
        queue.async {
            switch self.run(samples, language: language, vocabulary: vocabulary) {
            case .success(let text): reply(text, nil)
            case .failure(let message): reply(nil, message.text)
            }
        }
    }

    func streamBegin(id: Int, language: String?, vocabulary: String, lookaheadMs: Int, reply: @escaping @Sendable (String?) -> Void) {
        queue.async { reply(self.beginStream(id, language: language, vocabulary: vocabulary, lookaheadMs: lookaheadMs)) }
    }

    func streamFeed(id: Int, samples: Data, reply: @escaping @Sendable (String?, String?) -> Void) {
        queue.async {
            guard self.streamID == id, let session = self.session else { return reply(nil, nil) }
            let count = Int32(samples.count / MemoryLayout<Float>.size)
            guard count > 0 else { return reply(Self.streamText(session), nil) }
            let status = samples.withUnsafeBytes { raw in
                transcribe_stream_feed(session, raw.bindMemory(to: Float.self).baseAddress, count, nil)
            }
            guard status == TRANSCRIBE_OK else {
                self.streamID = nil
                return reply(nil, self.message(status, "Live transcription failed"))
            }
            reply(Self.streamText(session), nil)
        }
    }

    func streamFinish(id: Int, reply: @escaping @Sendable (String?, String?) -> Void) {
        queue.async {
            guard self.streamID == id, let session = self.session else { return reply(nil, "The live transcription had stopped") }
            self.streamID = nil
            let status = transcribe_stream_finalize(session, nil)
            guard status == TRANSCRIBE_OK, let text = transcribe_full_text(session) else {
                return reply(nil, self.message(status, "Live transcription failed"))
            }
            // The stream hit the model's length cap; the caller transcribes again.
            if transcribe_was_truncated(session) { return reply(nil, "The live transcription was cut short") }
            reply(Self.withoutLanguageTag(String(cString: text)), nil)
        }
    }

    func streamCancel(id: Int) {
        queue.async {
            guard self.streamID == id, let session = self.session else { return }
            self.streamID = nil
            transcribe_stream_reset(session)
        }
    }

    func unload(reply: @escaping @Sendable () -> Void) {
        queue.async {
            reply()
            // Exit without running C++ destructors: ggml-metal teardown can
            // assert (Handy engine_supervisor/worker.rs), and the OS takes
            // back every byte anyway.
            self.queue.asyncAfter(deadline: .now() + 0.1) { _exit(0) }
        }
    }

    struct Failure: Error {
        let text: String
    }

    private func loadOnQueue(_ path: String, backend: transcribe_backend_request) -> String? {
        if loadedPath == path, session != nil { return nil }
        freeModel()
        if !backendsReady {
            let status = transcribe_init_backends_default()
            guard status == TRANSCRIBE_OK else { return message(status, "Couldn't start the GPU backends") }
            backendsReady = true
        }
        var params = transcribe_model_load_params()
        transcribe_model_load_params_init(&params)
        params.backend = backend
        var loaded: OpaquePointer?
        let status = transcribe_model_load_file(path, &params, &loaded)
        guard status == TRANSCRIBE_OK, let loaded else { return message(status, "Couldn't load the model") }
        var opened: OpaquePointer?
        var sessionParams = transcribe_session_params()
        transcribe_session_params_init(&sessionParams)
        // On the GPU, the CPU only runs small ops like Parakeet's decoder.
        // The library's default of up to 8 threads spin between them: 23 s of
        // CPU for 46 s of streaming, against 7.7 s with 2 threads and the same
        // speed and text (docs/measurements.md). On the CPU, keep the default.
        sessionParams.n_threads = backend == TRANSCRIBE_BACKEND_CPU ? 0 : 2
        let sessionStatus = transcribe_session_init(loaded, &sessionParams, &opened)
        guard sessionStatus == TRANSCRIBE_OK, let opened else {
            transcribe_model_free(loaded)
            return message(sessionStatus, "This model can't transcribe")
        }
        model = loaded
        session = opened
        loadedPath = path
        return nil
    }

    private func beginStream(_ id: Int, language: String?, vocabulary: String, lookaheadMs: Int) -> String? {
        guard let session, let model else { return "No model is loaded" }
        // A stream left over from a dictation that never finished.
        transcribe_stream_reset(session)
        streamID = nil
        let cWords = Self.vocabularyWords(vocabulary, for: model)
        defer { cWords.forEach { free($0) } }
        func begin(_ language: String?) -> transcribe_status {
            Self.withRunParams(language: language, vocabulary: cWords) { params in
                Self.withStreamParams(model, lookaheadMs: lookaheadMs) { stream in
                    transcribe_stream_begin(session, params, stream)
                }
            }
        }
        var status = begin(language)
        if status == TRANSCRIBE_ERR_UNSUPPORTED_LANGUAGE, language != nil {
            status = begin(nil)
        }
        guard status == TRANSCRIBE_OK else { return message(status, "This model can't transcribe live") }
        streamID = id
        return nil
    }

    private func run(_ samples: Data, language: String?, vocabulary: String) -> Result<String, Failure> {
        guard let session, let model else { return .failure(Failure(text: "No model is loaded")) }
        if transcribe_stream_get_state(session) == TRANSCRIBE_STREAM_ACTIVE {
            transcribe_stream_reset(session)
            streamID = nil
        }
        let cWords = Self.vocabularyWords(vocabulary, for: model)
        defer { cWords.forEach { free($0) } }

        var status = runOnce(session, samples, language: language, vocabulary: cWords)
        if status == TRANSCRIBE_ERR_UNSUPPORTED_LANGUAGE, language != nil {
            // The model can't be told the language; let it detect it.
            status = runOnce(session, samples, language: nil, vocabulary: cWords)
        }
        if status == TRANSCRIBE_ERR_BACKEND, let path = loadedPath {
            // A GPU failure is recoverable: reload on the CPU and retry once.
            if let error = loadOnQueue(path, backend: TRANSCRIBE_BACKEND_CPU) { return .failure(Failure(text: error)) }
            guard let cpuSession = self.session else { return .failure(Failure(text: "No model is loaded")) }
            status = runOnce(cpuSession, samples, language: language, vocabulary: cWords)
        }
        guard status == TRANSCRIBE_OK, let current = self.session, let text = transcribe_full_text(current) else {
            return .failure(Failure(text: message(status, "Transcription failed")))
        }
        return .success(Self.withoutLanguageTag(String(cString: text)))
    }

    private func runOnce(_ session: OpaquePointer, _ samples: Data, language: String?, vocabulary: [UnsafeMutablePointer<CChar>?]) -> transcribe_status {
        let count = Int32(samples.count / MemoryLayout<Float>.size)
        return samples.withUnsafeBytes { raw in
            Self.withRunParams(language: language, vocabulary: vocabulary) { params in
                transcribe_run(session, raw.bindMemory(to: Float.self).baseAddress, count, params)
            }
        }
    }

    /// Run parameters with the language and custom words, valid only inside `body`.
    private static func withRunParams(
        language: String?, vocabulary: [UnsafeMutablePointer<CChar>?],
        _ body: (UnsafePointer<transcribe_run_params>) -> transcribe_status
    ) -> transcribe_status {
        var params = transcribe_run_params()
        transcribe_run_params_init(&params)
        let vocabularyPointers = vocabulary.map { UnsafePointer<CChar>($0) }
        return vocabularyPointers.withUnsafeBufferPointer { words in
            params.vocabulary = words.isEmpty ? nil : words.baseAddress
            params.n_vocabulary = Int32(words.count)
            guard let language else { return body(&params) }
            return language.withCString { code in
                params.language = code
                return body(&params)
            }
        }
    }

    /// Stream parameters with the trained latency setting that comes
    /// closest to `lookaheadMs` without going over (the smallest if none
    /// fits), from docs/models/parakeet-unified-en-0.6b.md and
    /// nemotron-3.5-asr-streaming-0.6b.md in transcribe.cpp. Other models,
    /// and 0, keep their defaults.
    private static func withStreamParams(
        _ model: OpaquePointer, lookaheadMs: Int,
        _ body: (UnsafePointer<transcribe_stream_params>) -> transcribe_status
    ) -> transcribe_status {
        var stream = transcribe_stream_params()
        transcribe_stream_params_init(&stream)
        // The extension starts with its transcribe_ext header, so a pointer
        // to the whole struct is a pointer to that header.
        func withFamily<Ext>(_ ext: inout Ext) -> transcribe_status {
            withUnsafeMutablePointer(to: &ext) { pointer in
                stream.family = UnsafeRawPointer(pointer).assumingMemoryBound(to: transcribe_ext.self)
                return body(&stream)
            }
        }
        func closest<T>(_ menu: [(ms: Int, value: T)]) -> T {
            (menu.last { $0.ms <= lookaheadMs } ?? menu[0]).value
        }
        if lookaheadMs > 0, transcribe_model_accepts_ext_kind(model, TRANSCRIBE_EXT_SLOT_STREAM, TRANSCRIBE_EXT_KIND_PARAKEET_BUFFERED_STREAM) {
            // Parakeet Unified: (chunk, right) in ms; the wait is chunk + right.
            let (chunk, right) = closest([
                (160, (80, 80)), (320, (160, 160)), (480, (160, 320)), (1120, (560, 560)), (2080, (1040, 1040)),
            ])
            var ext = transcribe_parakeet_buffered_stream_ext()
            transcribe_parakeet_buffered_stream_ext_init(&ext)
            ext.chunk_ms = Int32(chunk)
            ext.right_ms = Int32(right)
            return withFamily(&ext)
        }
        if lookaheadMs > 0, transcribe_model_accepts_ext_kind(model, TRANSCRIBE_EXT_SLOT_STREAM, TRANSCRIBE_EXT_KIND_PARAKEET_STREAM) {
            // Nemotron: right context in 80 ms frames, trained at 0, 3, 6 and 13.
            var ext = transcribe_parakeet_stream_ext()
            transcribe_parakeet_stream_ext_init(&ext)
            ext.att_context_right = Int32(closest([(80, 0), (320, 3), (560, 6), (1120, 13)]))
            return withFamily(&ext)
        }
        return body(&stream)
    }

    /// Custom words as C strings, if the model takes them. The caller frees them.
    private static func vocabularyWords(_ vocabulary: String, for model: OpaquePointer) -> [UnsafeMutablePointer<CChar>?] {
        let words = vocabulary.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty, transcribe_model_supports(model, TRANSCRIBE_FEATURE_VOCABULARY) else { return [] }
        return words.map { strdup($0) }
    }

    /// The stream's text so far: the settled part plus the part that may still change.
    private static func streamText(_ session: OpaquePointer) -> String? {
        var text = transcribe_stream_text()
        transcribe_stream_text_init(&text)
        guard transcribe_stream_get_text(session, &text) == TRANSCRIBE_OK else { return nil }
        func string(_ pointer: UnsafePointer<CChar>?, _ count: UInt64) -> String {
            guard let pointer, count > 0 else { return "" }
            return String(decoding: UnsafeRawBufferPointer(start: pointer, count: Int(count)), as: UTF8.self)
        }
        return withoutLanguageTag(string(text.committed_text, text.committed_text_bytes) + string(text.tentative_text, text.tentative_text_bytes))
    }

    /// Nemotron marks detected languages with a tag like "<lang-tr>".
    private static func withoutLanguageTag(_ text: String) -> String {
        text.replacing(/<lang-[A-Za-z-]+>\s*/, with: "")
    }

    private func freeModel() {
        if let session { transcribe_session_free(session) }
        if let model { transcribe_model_free(model) }
        session = nil
        model = nil
        loadedPath = nil
    }

    private func message(_ status: transcribe_status, _ context: String) -> String {
        let detail = transcribe_status_string(Int32(status.rawValue)).map { String(cString: $0) } ?? "error \(status.rawValue)"
        return "\(context): \(detail)"
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let engine = Engine()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: SottoEngineXPC.self)
        connection.exportedObject = engine
        connection.resume()
        return true
    }
}

// Avoids residency-set teardown asserts in ggml-metal (Handy #1902).
setenv("GGML_METAL_NO_RESIDENCY", "1", 1)
let delegate = ListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
