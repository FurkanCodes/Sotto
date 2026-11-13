import Foundation
import Observation
import SottoCore

/// Past dictations and usage stats, kept as two small JSON files in
/// Application Support. Written after each paste, never before it.
@Observable @MainActor
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []
    private(set) var stats = UsageStats()

    @ObservationIgnored private let historyURL: URL
    @ObservationIgnored private let statsURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = support.appendingPathComponent("Sotto", isDirectory: true)
        historyURL = folder.appendingPathComponent("history.json")
        statsURL = folder.appendingPathComponent("stats.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? Data(contentsOf: historyURL)).flatMap { try? decoder.decode([HistoryEntry].self, from: $0) } ?? []
        stats = (try? Data(contentsOf: statsURL)).flatMap { try? JSONDecoder().decode(UsageStats.self, from: $0) } ?? UsageStats()
    }

    /// Adds a dictation, newest first, then applies the retention setting.
    func add(_ entry: HistoryEntry, retentionDays: Int) {
        stats.record(words: entry.wordCount, seconds: entry.seconds, on: entry.date)
        save(stats, to: statsURL)
        guard retentionDays != 0 else { return }
        entries.insert(entry, at: 0)
        prune(retentionDays: retentionDays)
    }

    func prune(retentionDays: Int) {
        let kept = History.pruned(entries, now: Date(), retentionDays: retentionDays)
        if kept != entries { entries = kept }
        saveEntries()
    }

    func toggleStar(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].starred.toggle()
        saveEntries()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        saveEntries()
    }

    /// Clears everything except starred entries.
    func clearUnstarred() {
        entries.removeAll { !$0.starred }
        saveEntries()
    }

    private func saveEntries() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        write(data, to: historyURL)
    }

    private func save(_ stats: UsageStats, to url: URL) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        write(data, to: url)
    }

    private func write(_ data: Data, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            Log.app.error("Couldn't save \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
