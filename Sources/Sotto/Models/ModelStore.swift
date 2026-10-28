import CryptoKit
import Foundation
import Observation

/// Downloads, checks and removes catalog models. Files live in
/// Application Support/Sotto/Models. Downloads happen only when the user
/// asks, and a file is used only after its SHA-256 matches the catalog.
@Observable @MainActor
final class ModelStore {
    enum Download: Equatable {
        case running(Double)
        case checking
        case failed(String)
    }

    private(set) var downloads: [String: Download] = [:]
    /// Bumped when files change, so views re-read what's installed.
    private(set) var revision = 0

    @ObservationIgnored let folder: URL
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        folder = support.appendingPathComponent("Sotto/Models", isDirectory: true)
    }

    func path(for model: CatalogModel) -> URL? {
        guard let file = model.file else { return nil }
        return folder.appendingPathComponent(file.filename)
    }

    func isInstalled(_ model: CatalogModel) -> Bool {
        _ = revision
        guard let path = path(for: model) else { return false }
        return FileManager.default.fileExists(atPath: path.path)
    }

    var installed: [CatalogModel] {
        ModelCatalog.models.filter(isInstalled)
    }

    func download(_ model: CatalogModel) {
        guard tasks[model.id] == nil, let file = model.file, let url = model.downloadURL, let target = path(for: model) else { return }
        downloads[model.id] = .running(0)
        tasks[model.id] = Task { [weak self] in
            do {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let staged = target.appendingPathExtension("partial")
                try? FileManager.default.removeItem(at: staged)
                if let handyCopy = Self.handyCopy(of: file) {
                    // Already downloaded by Handy: a copy is instant on APFS.
                    try FileManager.default.copyItem(at: handyCopy, to: staged)
                } else {
                    try await Self.fetch(url, to: staged) { fraction in
                        Task { @MainActor in self?.downloads[model.id] = .running(fraction) }
                    }
                }
                await MainActor.run { self?.downloads[model.id] = .checking }
                let hash = try await Task.detached { try Self.sha256(of: staged) }.value
                guard hash == file.sha256 else {
                    try? FileManager.default.removeItem(at: staged)
                    throw DownloadError.checksum
                }
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: staged, to: target)
                await MainActor.run {
                    self?.downloads[model.id] = nil
                    self?.revision += 1
                }
            } catch is CancellationError {
                await MainActor.run { self?.downloads[model.id] = nil }
            } catch {
                await MainActor.run { self?.downloads[model.id] = .failed(error.localizedDescription) }
            }
            await MainActor.run { self?.tasks[model.id] = nil }
        }
    }

    func cancel(_ model: CatalogModel) {
        tasks[model.id]?.cancel()
    }

    func delete(_ model: CatalogModel) {
        guard let path = path(for: model) else { return }
        try? FileManager.default.removeItem(at: path)
        revision += 1
    }

    enum DownloadError: LocalizedError {
        case checksum
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .checksum: "The download was damaged. Try again."
            case .http(let code): "The download failed (HTTP \(code))."
            }
        }
    }

    // MARK: - Work off the main thread

    private nonisolated static func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
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
                        continuation.resume(throwing: DownloadError.http(http.statusCode))
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

    private nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The same file in Handy's model folder, if Handy downloaded it.
    private nonisolated static func handyCopy(of file: CatalogModel.File) -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let candidate = support.appendingPathComponent("com.pais.handy/models/\(file.filename)")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: candidate.path),
              (attributes[.size] as? NSNumber)?.int64Value == file.size
        else { return nil }
        return candidate
    }
}

/// Holds the download task so cancellation can reach it.
private final class TaskBox: @unchecked Sendable {
    var task: URLSessionDownloadTask?
    var observation: NSKeyValueObservation?
}
