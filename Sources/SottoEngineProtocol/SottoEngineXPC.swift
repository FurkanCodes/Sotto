import Foundation

/// What the app asks of the SottoEngine helper, which runs transcribe.cpp
/// models in their own process: a crash there never takes Sotto down, and
/// unloading ends the process so all of the model's memory goes back.
@objc public protocol SottoEngineXPC {
    /// Loads a GGUF model. Replies with an error message, or nil on success.
    func load(modelPath: String, reply: @escaping @Sendable (String?) -> Void)

    /// Transcribes 16 kHz mono Float32 samples. `language` is a code like
    /// "tr", or nil for automatic. `vocabulary` holds custom words, one per
    /// line, for models that accept them. Replies with the text or an error.
    func transcribe(samples: Data, language: String?, vocabulary: String, reply: @escaping @Sendable (String?, String?) -> Void)

    /// Starts a live stream on the loaded model, for models built to stream
    /// (Nemotron, Parakeet Unified). `id` tags the stream; calls for any
    /// other id are ignored, so late feeds from an earlier stream do no
    /// harm. Replies with an error message, or nil on success.
    func streamBegin(id: Int, language: String?, vocabulary: String, reply: @escaping @Sendable (String?) -> Void)

    /// Feeds more 16 kHz mono Float32 audio. Replies with the text so far,
    /// or an error. Both are nil for a stale id.
    func streamFeed(id: Int, samples: Data, reply: @escaping @Sendable (String?, String?) -> Void)

    /// Flushes the stream and replies with the final text, or an error.
    func streamFinish(id: Int, reply: @escaping @Sendable (String?, String?) -> Void)

    /// Abandons the stream.
    func streamCancel(id: Int)

    /// Frees the model and ends the helper process.
    func unload(reply: @escaping @Sendable () -> Void)
}

public enum SottoEngineService {
    public static let name = "com.furkan.sotto.engine"
}
