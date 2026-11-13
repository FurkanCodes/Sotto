import Foundation
import Observation
import SottoCore

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
    /// Settings → Models → Run models on; decides which build each model uses.
    var engine = ModelEngine.automatic

    @ObservationIgnored let folder: URL
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        folder = support.appendingPathComponent("Sotto/Models", isDirectory: true)
    }

    /// The Neural Engine build the model uses under the current setting, or nil for the GPU build.
    func neural(for model: CatalogModel) -> NeuralModel? {
        model.neural(for: engine)
    }

    /// The size of the build the model uses under the current setting.
    func downloadSize(for model: CatalogModel) -> Int64? {
        neural(for: model)?.size ?? model.file?.size
    }

    /// The GGUF file, or for a Neural Engine build, its folder of CoreML files.
    func path(for model: CatalogModel) -> URL? {
        if let neural = neural(for: model) { return folder.appendingPathComponent(neural.folderName, isDirectory: true) }
        guard let file = model.file else { return nil }
        return folder.appendingPathComponent(file.filename)
    }

    func isInstalled(_ model: CatalogModel) -> Bool {
        _ = revision
        guard let path = path(for: model) else { return false }
        if neural(for: model) != nil { return ModelDownload.isComplete(path) }
        return FileManager.default.fileExists(atPath: path.path)
    }

    var installed: [CatalogModel] {
        ModelCatalog.models.filter(isInstalled)
    }

    func download(_ model: CatalogModel) {
        if let neural = neural(for: model) {
            downloadNeural(model, neural)
            return
        }
        guard tasks[model.id] == nil, let file = model.file, let url = model.downloadURL, let target = path(for: model) else { return }
        downloads[model.id] = .running(0)
        tasks[model.id] = Task { [weak self] in
            do {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let staged = target.appendingPathExtension("partial")
                try? FileManager.default.removeItem(at: staged)
                try await ModelDownload.fetch(url, to: staged) { fraction in
                    Task { @MainActor in self?.downloads[model.id] = .running(fraction) }
                }
                await MainActor.run { self?.downloads[model.id] = .checking }
                guard try await ModelDownload.sha256(staged) == file.sha256 else {
                    try? FileManager.default.removeItem(at: staged)
                    throw ModelDownload.Failure.checksum
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

    private func downloadNeural(_ model: CatalogModel, _ neural: NeuralModel) {
        guard tasks[model.id] == nil, let target = path(for: model) else { return }
        downloads[model.id] = .running(0)
        tasks[model.id] = Task { [weak self] in
            do {
                try await ModelDownload.installPinned(neural, at: target) { fraction in
                    Task { @MainActor in self?.downloads[model.id] = .running(fraction) }
                }
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

    /// Deletes both builds of the model, if present.
    func delete(_ model: CatalogModel) {
        if let file = model.file { try? FileManager.default.removeItem(at: folder.appendingPathComponent(file.filename)) }
        if let build = model.neuralBuild { try? FileManager.default.removeItem(at: folder.appendingPathComponent(build.folderName)) }
        revision += 1
    }
}
