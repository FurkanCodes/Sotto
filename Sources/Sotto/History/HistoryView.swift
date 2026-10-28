import AppKit
import SottoCore
import SwiftUI

struct HistoryView: View {
    let history: HistoryStore
    let retentionDays: Int
    @State private var search = ""
    @State private var confirmingClear = false

    private var filtered: [HistoryEntry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return history.entries }
        return history.entries.filter {
            $0.text.localizedCaseInsensitiveContains(query) || ($0.appName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var days: [(title: String, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { day in
            let title: String
            if calendar.isDateInToday(day) {
                title = "Today"
            } else if calendar.isDateInYesterday(day) {
                title = "Yesterday"
            } else {
                title = day.formatted(date: .complete, time: .omitted)
            }
            return (title, groups[day] ?? [])
        }
    }

    var body: some View {
        let week = history.stats.week(endingOn: Date())
        Form {
            Section("This week") {
                HStack(spacing: 0) {
                    stat("Words", week.words.formatted())
                    Divider().frame(height: 32)
                    stat("Time saved", "\(Int(UsageStats.minutesSaved(week).rounded())) min")
                    Divider().frame(height: 32)
                    stat("Dictations", week.dictations.formatted())
                }
            }

            Section {
                TextField("Search dictations", text: $search, prompt: Text("Search dictations"))
                    .labelsHidden()
            }

            if filtered.isEmpty {
                Section {
                    Text(search.isEmpty ? emptyHint : "No dictations match “\(search)”.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(days, id: \.title) { day in
                    Section(day.title) {
                        ForEach(day.entries) { entry in
                            HistoryRow(entry: entry, history: history)
                        }
                    }
                }
            }

            Section {
                HStack {
                    Text(retentionText).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear History…") { confirmingClear = true }
                        .disabled(history.entries.allSatisfy(\.starred))
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear your dictation history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { history.clearUnstarred() }
        } message: {
            Text("Starred dictations are kept. This can't be undone.")
        }
    }

    private var emptyHint: String {
        retentionDays == 0
            ? "History is off. Turn it on in Settings › Privacy."
            : "Your dictations appear here."
    }

    private var retentionText: String {
        switch retentionDays {
        case 0: "History is off. Starred dictations are kept."
        case let days where days < 0: "Kept until you delete them."
        case 1: "Kept for 1 day. Starred dictations are kept longer."
        case let days: "Kept for \(days) days. Starred dictations are kept longer."
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .semibold).monospacedDigit())
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let history: HistoryStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text).lineLimit(4).textSelection(.enabled)
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Button {
                    history.toggleStar(entry.id)
                } label: {
                    Image(systemName: entry.starred ? "star.fill" : "star")
                        .foregroundStyle(entry.starred ? .yellow : .secondary)
                }
                .help(entry.starred ? "Unstar" : "Star, so it's kept")
                .accessibilityLabel(entry.starred ? "Unstar" : "Star")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy")
                .accessibilityLabel("Copy")
                Button {
                    history.delete(entry.id)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete")
                .accessibilityLabel("Delete")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var details: String {
        var parts = [entry.appName ?? "Not pasted", entry.date.formatted(date: .omitted, time: .shortened)]
        parts.append(String(format: "%d:%02d", Int(entry.seconds) / 60, Int(entry.seconds) % 60))
        return parts.joined(separator: " · ")
    }
}
