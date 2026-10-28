import Foundation
import SottoEngineProtocol

/// A transcribe.cpp model, run by the SottoEngine XPC helper. If the helper
/// crashes, macOS relaunches it on the next call and the model is loaded
/// again; the app itself is unaffected.
actor HelperEngine: SpeechEngine {
    enum HelperError: LocalizedError {
        case failed(String)
        case lost

        var errorDescription: String? {
            switch self {
            case .failed(let message): message
            case .lost: "The speech engine stopped unexpectedly."
            }
        }
    }

    private var connection: NSXPCConnection?
    private var loadedPath: String?
    private var modelPath: String?
    private var language: String?
    private var vocabulary = ""

    var isLoaded: Bool { loadedPath != nil && loadedPath == modelPath }

    /// Sets the model file, language ("tr", or nil for automatic) and custom
    /// words. A new model file takes effect on the next load.
    func configure(modelPath: String, language: String?, vocabulary: [String]) {
        self.modelPath = modelPath
        self.language = language
        self.vocabulary = vocabulary.joined(separator: "\n")
    }

    func load() async throws {
        guard let modelPath else { throw HelperError.failed("No model is chosen") }
        if loadedPath == modelPath { return }
        let error: String? = try await call { proxy, done in
            proxy.load(modelPath: modelPath) { done(.success($0)) }
        }
        if let error { throw HelperError.failed(error) }
        loadedPath = modelPath
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await load()
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let language = self.language
        let vocabulary = self.vocabulary
        let (text, error): (String?, String?) = try await call { proxy, done in
            proxy.transcribe(samples: data, language: language, vocabulary: vocabulary) { done(.success(($0, $1))) }
        }
        if let error { throw HelperError.failed(error) }
        return text ?? ""
    }

    func warmUp() async {
        _ = try? await transcribe([Float](repeating: 0, count: 16_000))
    }

    /// Ends the helper process, which gives back all of the model's memory.
    func unload() async {
        guard connection != nil else { return }
        let _: Void? = try? await call { proxy, done in
            proxy.unload { done(.success(())) }
        }
        connection?.invalidate()
        connection = nil
        loadedPath = nil
    }

    private func lost() {
        loadedPath = nil
    }

    private func proxy(onError: @escaping @Sendable (Error) -> Void) -> SottoEngineXPC? {
        if connection == nil {
            let new = NSXPCConnection(serviceName: SottoEngineService.name)
            new.remoteObjectInterface = NSXPCInterface(with: SottoEngineXPC.self)
            new.interruptionHandler = { [weak self] in
                guard let self else { return }
                Task { await self.lost() }
            }
            new.invalidationHandler = { [weak self] in
                guard let self else { return }
                Task { await self.lost() }
            }
            new.resume()
            connection = new
        }
        return connection?.remoteObjectProxyWithErrorHandler(onError) as? SottoEngineXPC
    }

    /// Sends one message and waits for its reply, or for the connection to fail.
    private func call<T: Sendable>(_ send: (SottoEngineXPC, @escaping @Sendable (Result<T, Error>) -> Void) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let once = Once(continuation)
            guard let proxy = proxy(onError: { _ in once.resume(.failure(HelperError.lost)) }) else {
                once.resume(.failure(HelperError.lost))
                return
            }
            send(proxy) { once.resume($0) }
        }
    }
}

/// Resumes a continuation at most once: XPC can report an error after the
/// reply, or never reply when the helper dies.
private final class Once<T: Sendable>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
