import AppKit
import SottoCore
import SwiftUI

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, shortcut, models, dictionary, history, privacy, about
        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .shortcut: "Shortcut"
            case .models: "Models"
            case .dictionary: "Dictionary"
            case .history: "History"
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
            case .history: "clock.arrow.circlepath"
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
                case .general: GeneralPane(store: controller.store) { pane = .shortcut }
                case .shortcut: ShortcutPane(store: controller.store)
                case .models: ModelsPane(controller: controller, store: controller.store)
                case .dictionary: DictionaryPane(store: controller.store)
                case .history: HistoryView(history: controller.history, retentionDays: controller.store.settings.historyRetentionDays)
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
    let changeKey: () -> Void
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var inputs = AudioDevices.inputs()

    var body: some View {
        Form {
            Section("Dictation") {
                LabeledContent("Dictation key") {
                    HStack(spacing: 8) {
                        Keycap(store.settings.dictationKey.keycapLabel)
                        Button("Change…", action: changeKey)
                    }
                }
                Toggle(isOn: $store.settings.tapToKeepListening) {
                    Text("Tap to keep listening")
                    Text("A quick tap starts hands-free mode. Tap again to finish.")
                }
                Toggle(isOn: $store.settings.removeFillerWords) {
                    Text("Remove filler words")
                    Text("Takes out um, uh and hmm.")
                }
                Toggle(isOn: $store.settings.fixSelfCorrections) {
                    Text("Fix spoken corrections")
                    Text("“At 2, actually 3” becomes “at 3”. Only clear corrections of numbers, days and names.")
                }
                Toggle(isOn: $store.settings.sayToSend) {
                    Text("Say “send it” to press Return")
                    Text("End a dictation with “send it” to send the message.")
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
                Toggle(isOn: $store.settings.showLiveText) {
                    Text("Show text while dictating")
                    Text("Finished sentences appear above the pill as you talk.")
                }
                Picker("Position", selection: $store.settings.pillPosition) {
                    Text("Bottom of the screen").tag(PillPosition.bottom)
                    Text("Top of the screen").tag(PillPosition.top)
                }
                Toggle("Play sounds", isOn: $store.settings.playSounds)
            }
            Section("System") {
                Toggle(isOn: $store.settings.lowerOtherAudio) {
                    Text("Lower other audio while dictating")
                    Text("Turns music and videos down while you talk, then back up.")
                }
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
            Section {
                Toggle(isOn: $store.settings.matchStyleToApp) {
                    Text("Match the style to the app")
                    Text("Chat apps get casual text: no capital at the start, no period at the end. Code editors and terminals get plain text with no trailing space. Everything else gets proper sentences.")
                }
                if store.settings.matchStyleToApp {
                    ForEach($store.settings.styleRules) { $rule in
                        HStack {
                            Text(rule.app.name)
                            Spacer()
                            Picker("Style", selection: $rule.style) {
                                ForEach(TextStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                            RemoveButton(name: rule.app.name) {
                                store.settings.styleRules.removeAll { $0.id == rule.id }
                            }
                        }
                    }
                    Button("Set a Style for an App…") {
                        if let app = AppPicker.choose(), !store.settings.styleRules.contains(where: { $0.app == app }) {
                            store.settings.styleRules.append(StyleRule(app: app, style: Styles.defaultStyle(forBundleID: app.bundleID)))
                        }
                    }
                }
            } header: {
                Text("Styles")
            } footer: {
                Text("Only capitals, the final period and the trailing space change, never your words. “I”, acronyms and your custom words keep their capitals.")
            }
            Section {
                ForEach($store.settings.autoSendApps) { $rule in
                    HStack {
                        Text(rule.app.name)
                        Spacer()
                        Picker("Key", selection: $rule.withCommand) {
                            Text("Return").tag(false)
                            Text("⌘ Return").tag(true)
                        }
                        .labelsHidden()
                        .fixedSize()
                        RemoveButton(name: rule.app.name) {
                            store.settings.autoSendApps.removeAll { $0.id == rule.id }
                        }
                    }
                }
                Button("Add App…") {
                    if let app = AppPicker.choose(), !store.settings.autoSendApps.contains(where: { $0.app == app }) {
                        store.settings.autoSendApps.append(AutoSendRule(app: app))
                    }
                }
            } header: {
                Text("Always send")
            } footer: {
                Text("In these apps, Sotto presses Return after inserting your text, so messages send right away.")
            }
            PrivacyFooter()
        }
        .formStyle(.grouped)
    }
}

extension TextStyle {
    var title: String {
        switch self {
        case .standard: "Standard"
        case .casual: "Casual"
        case .plain: "Plain"
        }
    }
}

/// A small minus button for removing a row from a list.
struct RemoveButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .help("Remove \(name)")
        .accessibilityLabel("Remove \(name)")
    }
}

/// A key drawn like a physical keycap, as in the design.
struct Keycap: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            .accessibilityLabel("Key: \(label)")
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
            Section {
                Picker("Mouse button", selection: $store.settings.mouseButton) {
                    Text("None").tag(Int?.none)
                    Text("Middle button").tag(Int?.some(2))
                    Text("Back button").tag(Int?.some(3))
                    Text("Forward button").tag(Int?.some(4))
                }
            } footer: {
                Text("The mouse button works like the dictation key: hold to talk, or click to keep listening.")
            }
            Section {
                ForEach(store.settings.skipApps) { app in
                    HStack {
                        Text(app.name)
                        Spacer()
                        RemoveButton(name: app.name) { store.settings.skipApps.removeAll { $0 == app } }
                    }
                }
                Button("Add App…") {
                    if let app = AppPicker.choose(), !store.settings.skipApps.contains(app) {
                        store.settings.skipApps.append(app)
                    }
                }
            } header: {
                Text("Apps to skip")
            } footer: {
                Text("The dictation key does nothing in these apps, such as games or password managers.")
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
                        Text(controller.modelReady ? "Loaded and ready." : "Not loaded right now. It loads while you start talking.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("Default", systemImage: "checkmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
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
    @State private var replaceFrom = ""
    @State private var replaceTo = ""
    @State private var snippetTrigger = ""
    @State private var snippetText = ""
    @State private var handyWords = HandyImport.customWords()

    private var trimmed: String { newWord.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Add a name or term", text: $newWord)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(trimmed.isEmpty)
                }
                if let handyWords, !handyWords.isEmpty {
                    Button("Import \(handyWords.count) Words from Handy") {
                        for word in handyWords where !store.settings.customWords.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                            store.settings.customWords.append(word)
                        }
                        self.handyWords = []
                    }
                }
                Toggle(isOn: $store.settings.learnFromCorrections) {
                    Text("Learn from my corrections")
                    Text("If you fix a dictated name or term by hand, Sotto offers to add it here. The text field is read only in memory, for 20 seconds after a paste, and never in password fields.")
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
            Section {
                HStack {
                    TextField("When I say", text: $replaceFrom)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("Write", text: $replaceTo)
                    Button("Add") {
                        let from = replaceFrom.trimmingCharacters(in: .whitespaces)
                        guard !from.isEmpty else { return }
                        store.settings.replacements.append(Replacement(from: from, to: replaceTo))
                        replaceFrom = ""
                        replaceTo = ""
                    }
                    .disabled(replaceFrom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(store.settings.replacements, id: \.self) { rule in
                    HStack {
                        Text(rule.from)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(rule.to.isEmpty ? "(nothing)" : rule.to).foregroundStyle(rule.to.isEmpty ? .secondary : .primary)
                        Spacer()
                        RemoveButton(name: rule.from) { store.settings.replacements.removeAll { $0 == rule } }
                    }
                }
            } header: {
                Text("Replacements")
            } footer: {
                Text("Exact swaps, like “gee mail” → “Gmail” or “dot com” → “.com”.")
            }
            Section {
                TextField("Trigger, like “my address”", text: $snippetTrigger)
                TextField("Text to insert", text: $snippetText, axis: .vertical).lineLimit(2...6)
                Button("Add Snippet") {
                    let trigger = snippetTrigger.trimmingCharacters(in: .whitespaces)
                    guard !trigger.isEmpty, !snippetText.isEmpty else { return }
                    store.settings.snippets.append(Snippet(trigger: trigger, text: snippetText))
                    snippetTrigger = ""
                    snippetText = ""
                }
                .disabled(snippetTrigger.trimmingCharacters(in: .whitespaces).isEmpty || snippetText.isEmpty)
                ForEach(store.settings.snippets, id: \.self) { snippet in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snippet.trigger).fontWeight(.medium)
                            Text(snippet.text).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        RemoveButton(name: snippet.trigger) { store.settings.snippets.removeAll { $0 == snippet } }
                    }
                }
            } header: {
                Text("Snippets")
            } footer: {
                Text("Say the trigger and Sotto types the text. Use {date}, {time} or {clipboard} inside it.")
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
                Label("Your dictation history is stored only on this Mac, encrypted with your login.", systemImage: "clock.arrow.circlepath")
                Label("No analytics, no crash reports, no account.", systemImage: "hand.raised")
            }
            Section("History") {
                Picker("Keep dictations", selection: Bindable(controller.store).settings.historyRetentionDays) {
                    Text("Don't keep").tag(0)
                    Text("For 1 day").tag(1)
                    Text("For 7 days").tag(7)
                    Text("For 30 days").tag(30)
                    Text("Until I delete them").tag(-1)
                }
                Button("Clear History") { controller.history.clearUnstarred() }
                    .disabled(controller.history.entries.allSatisfy(\.starred))
                Button("Forget Last Transcript") { controller.forgetLastTranscript() }
                    .disabled(controller.last == nil)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

/// The license notices stay in the app bundle (THIRD_PARTY_NOTICES.md), as
/// the MIT and Apache licenses require, but aren't shown here.
private struct AboutPane: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Sotto").font(.system(size: 34, weight: .semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Offline voice dictation for macOS.")
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
