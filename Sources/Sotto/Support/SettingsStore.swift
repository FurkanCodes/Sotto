import Foundation
import Observation
import SottoCore

/// Holds the settings in memory and writes them to disk when they change.
/// Disk is read once, at launch; nothing on the dictation path reads it.
@Observable @MainActor
final class SettingsStore {
    var settings: SottoSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            onChange?(settings)
        }
    }

    @ObservationIgnored var onChange: ((SottoSettings) -> Void)?
    @ObservationIgnored private let url: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        url = support.appendingPathComponent("Sotto", isDirectory: true).appendingPathComponent("settings.json")
        settings = (try? Data(contentsOf: url)).map(SottoSettings.decode) ?? SottoSettings()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try settings.encoded().write(to: url, options: .atomic)
        } catch {
            Log.app.error("Couldn't save settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
