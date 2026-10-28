import AppKit
import SottoCore
import SwiftUI

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, shortcut, models, dictionary, privacy, about
        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .shortcut: "Shortcut"
            case .models: "Models"
            case .dictionary: "Dictionary"
            case .privacy: "Privacy"
            case .about: "About"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .shortcut: "keyboard"
            case .models: "cpu"
            case .dictionary: "book.closed"
            case .privacy: "lock"
            case .about: "info.circle"
            }
        }
    }

    let controller: DictationController
    @State private var pane: Pane? = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.icon).tag(pane)
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general: GeneralPane(store: controller.store)
                case .shortcut: ShortcutPane(store: controller.store)
                case .models: ModelsPane(controller: controller, store: controller.store)
                case .dictionary: DictionaryPane(store: controller.store)
                case .privacy: PrivacyPane(controller: controller)
                case .about: AboutPane()
                }
            }
            .navigationTitle((pane ?? .general).title)
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Bindable var store: SettingsStore
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var inputs = AudioDevices.inputs()

    var body: some View {
        Form {
            Section("Dictation") {
                Toggle(isOn: $store.settings.tapToKeepListening) {
                    Text("Tap to keep listening")
                    Text("A quick tap starts hands-free mode. Tap again to finish.")
                }
                Toggle(isOn: $store.settings.removeFillerWords) {
                    Text("Remove filler words")
                    Text("Takes out um, uh and hmm.")
                }
                LabeledContent {
                    Text("Detected automatically")
                } label: {
                    Text("Language")
                    Text("Parakeet v3 understands 25 European languages.")
                }
            }
            Section("Pill") {
                Toggle("Show pill while dictating", isOn: $store.settings.showPill)
                Picker("Position", selection: $store.settings.pillPosition) {
                    Text("Bottom of the screen").tag(PillPosition.bottom)
                    Text("Top of the screen").tag(PillPosition.top)
                }
                Toggle("Play sounds", isOn: $store.settings.playSounds)
            }
            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LoginItem.setEnabled(enabled)
                        launchAtLogin = LoginItem.isEnabled
                    }
                Picker("Microphone", selection: $store.settings.microphoneUID) {
                    Text(AudioDevices.defaultInputName().map { "System Default (\($0))" } ?? "System Default")
                        .tag(String?.none)
                    ForEach(inputs) { input in
                        Text(input.name).tag(String?.some(input.id))
                    }
                }
            }
            PrivacyFooter()
        }
        .formStyle(.grouped)
    }
}

private struct PrivacyFooter: View {
    var body: some View {
        Section {
            Label("Everything stays on this Mac. After the model download, Sotto makes no network connections.", systemImage: "lock")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shortcut

private struct ShortcutPane: View {
    @Bindable var store: SettingsStore

    var body: some View {
        let key = store.settings.dictationKey
        Form {
            Section {
                Picker("Dictation key", selection: $store.settings.dictationKey) {
                    ForEach(DictationKey.allCases, id: \.self) { key in
                        Text(key.title).tag(key)
                    }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("A single key keeps working in password fields, where macOS blocks key combinations.")
            }
            Section("How it works") {
                LabeledContent("Hold \(key.symbol)", value: "Talk, then let go to insert the text")
                if store.settings.tapToKeepListening {
                    LabeledContent("Tap \(key.symbol)", value: "Keeps listening until you tap again")
                }
                LabeledContent("Esc", value: "Cancels")
                LabeledContent("Another key while holding", value: "Cancels, so \(key.symbol) still types characters like @")
            }
            if key == .fn {
                Section {
                    Text("In System Settings, set Keyboard › “Press 🌐 key to” to “Do Nothing”, so macOS doesn't open its own dictation or emoji picker too.")
                    Button("Open Keyboard Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Models

private struct ModelsPane: View {
    let controller: DictationController
    @Bindable var store: SettingsStore
    @State private var sizeOnDisk: String?

    var body: some View {
        Form {
            Section("In use") {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Parakeet TDT 0.6B v3").font(.headline)
                        Text("NVIDIA · 25 languages, detected automatically · runs on the Neural Engine to save battery")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if controller.modelReady {
                        Label("Loaded", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Not loaded", systemImage: "moon").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Size on disk", value: sizeOnDisk ?? "…")
                Picker(selection: $store.settings.unloadAfterMinutes) {
                    Text("After 1 minute").tag(1)
                    Text("After 5 minutes").tag(5)
                    Text("After 15 minutes").tag(15)
                    Text("After 1 hour").tag(60)
                    Text("Never").tag(0)
                } label: {
                    Text("Unload when idle")
                    Text("Frees the model's memory. The next dictation loads it again, while you talk.")
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([controller.modelDirectory])
                }
            }
            Section {
                Text("Whisper, Nemotron and other models are coming in a later version.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            let directory = controller.modelDirectory
            let bytes = await Task.detached { Self.size(of: directory) }.value
            sizeOnDisk = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
    }

    private nonisolated static func size(of directory: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

// MARK: - Dictionary

private struct DictionaryPane: View {
    @Bindable var store: SettingsStore
    @State private var newWord = ""

    private var trimmed: String { newWord.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Add a name or term", text: $newWord)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(trimmed.isEmpty)
                }
            } header: {
                Text("Custom words")
            } footer: {
                Text("Sotto fixes these when they're misheard, like “Furcan” → “Furkan” or “Chat G P T” → “ChatGPT”. It works for words written in English letters and numbers.")
            }
            Section {
                if store.settings.customWords.isEmpty {
                    Text("No custom words yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(store.settings.customWords, id: \.self) { word in
                        HStack {
                            Text(word)
                            Spacer()
                            Button {
                                store.settings.customWords.removeAll { $0 == word }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(word)")
                            .accessibilityLabel("Remove \(word)")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        let word = trimmed
        guard !word.isEmpty else { return }
        if !store.settings.customWords.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
            store.settings.customWords.append(word)
        }
        newWord = ""
    }
}

// MARK: - Privacy

private struct PrivacyPane: View {
    let controller: DictationController

    var body: some View {
        Form {
            Section {
                Label("Speech is turned into text on this Mac, by its Neural Engine.", systemImage: "cpu")
                Label("After the model download, Sotto makes no network connections.", systemImage: "network.slash")
                Label("Only your last transcript is kept, in memory. It's gone when Sotto quits.", systemImage: "clock.arrow.circlepath")
                Label("No analytics, no crash reports, no account.", systemImage: "hand.raised")
            }
            Section {
                Button("Forget Last Transcript") { controller.forgetLastTranscript() }
                    .disabled(controller.last == nil)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutPane: View {
    @State private var showingAcknowledgements = false
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Sotto").font(.system(size: 34, weight: .semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Offline voice dictation for macOS.")
            Button("Acknowledgements") { showingAcknowledgements = true }
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showingAcknowledgements) {
            VStack(alignment: .trailing, spacing: 0) {
                ScrollView {
                    Text(Self.acknowledgements)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                Divider()
                Button("Done") { showingAcknowledgements = false }
                    .keyboardShortcut(.defaultAction)
                    .padding(12)
            }
            .frame(width: 600, height: 480)
        }
    }

    private static var acknowledgements: String {
        guard let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "Handy (MIT), FluidAudio (Apache 2.0), Parakeet TDT 0.6B v3 by NVIDIA (CC-BY-4.0), Silero VAD (MIT)." }
        return text
    }
}
