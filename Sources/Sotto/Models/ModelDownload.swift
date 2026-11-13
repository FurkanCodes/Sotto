import CryptoKit
import Foundation

/// Model downloads: fetching a file, checking its SHA-256, and installing a
/// pinned set of CoreML files (Neural Engine catalog models, the built-in
/// Parakeet v3 and the Silero voice detector). Nothing is used until every
/// file in it has passed its check.
enum ModelDownload {
    enum Failure: LocalizedError {
        case checksum
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .checksum: "The download was damaged. Try again."
            case .http(let code): "The download failed (HTTP \(code))."
            }
        }
    }

    /// Written into a pinned model's folder once every file has passed its check.
    static let completeMarker = ".complete"

    static func isComplete(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(completeMarker).path)
    }

    /// Installs a pinned model into `target`: each file is taken from `reuse`
    /// if a file there has the pinned SHA-256 (a copy is a clone on APFS, so
    /// it takes no extra space), and downloaded otherwise. Everything lands in
    /// a staging folder first and moves into place only when complete.
    static func installPinned(
        _ model: NeuralModel, at target: URL, reuse: URL? = nil,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let staged = target.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: staged)
        do {
            var done: Int64 = 0
            for file in model.files {
                try Task.checkCancellation()
                let localPath = model.localPath(for: file)
                let destination = staged.appendingPathComponent(localPath)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let existing = reuse?.appendingPathComponent(localPath),
                   FileManager.default.fileExists(atPath: existing.path),
                   (try? await sha256(existing)) == file.sha256 {
                    try FileManager.default.copyItem(at: existing, to: destination)
                } else {
                    guard let url = model.url(for: file) else { throw URLError(.badURL) }
                    let before = done
                    try await fetch(url, to: destination) { fraction in
                        progress((Double(before) + fraction * Double(file.size)) / Double(max(model.size, 1)))
                    }
                    guard try await sha256(destination) == file.sha256 else { throw Failure.checksum }
                }
                done += file.size
                progress(Double(done) / Double(max(model.size, 1)))
            }
            FileManager.default.createFile(atPath: staged.appendingPathComponent(completeMarker).path, contents: Data())
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: staged, to: target)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
    }

    /// The SHA-256 of a file, computed off the caller's thread.
    static func sha256(_ url: URL) async throws -> String {
        try await Task.detached {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }

    static func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let box = TaskBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = URLSession.shared.downloadTask(with: url) { temporary, response, error in
                    box.observation?.invalidate()
                    if let error {
                        continuation.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
                        return
                    }
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        continuation.resume(throwing: Failure.http(http.statusCode))
                        return
                    }
                    guard let temporary else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    // The temporary file is deleted when this handler returns.
                    do {
                        try FileManager.default.moveItem(at: temporary, to: destination)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                box.task = task
                box.observation = task.progress.observe(\.fractionCompleted) { value, _ in
                    progress(value.fractionCompleted)
                }
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
    }
}

/// Holds the download task so cancellation can reach it.
private final class TaskBox: @unchecked Sendable {
    var task: URLSessionDownloadTask?
    var observation: NSKeyValueObservation?
}
