import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Drop in an audio or video file and get its text, on this Mac.
struct FileTranscriptionView: View {
    enum Phase: Equatable {
        case waiting
        case working(String)
        case done(name: String, text: String)
        case failed(String)
    }

    let controller: DictationController
    @State private var phase = Phase.waiting
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 16) {
            switch phase {
            case .waiting:
                dropZone
            case .working(let name):
                Spacer()
                ProgressView()
                Text("Transcribing “\(name)”…").foregroundStyle(.secondary)
                Text("This runs on your Mac. A one-hour recording takes a minute or two.")
                    .font(.callout).foregroundStyle(.tertiary)
                Spacer()
            case .done(let name, let text):
                HStack {
                    Text(name).font(.headline).lineLimit(1)
                    Spacer()
                    Text("\(text.split(whereSeparator: \.isWhitespace).count.formatted()) words")
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    Text(text.isEmpty ? "No speech found in this file." : text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Button("Transcribe Another…") { choose() }
                    Spacer()
                    Button("Save as Text…") { save(text, name: name) }.disabled(text.isEmpty)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.isEmpty)
                }
            case .failed(let message):
                Spacer()
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text(message).multilineTextAlignment(.center)
                Button("Choose Another File…") { choose() }
                Spacer()
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, case .waiting = phase else { return false }
            transcribe(url)
            return true
        } isTargeted: { targeted = $0 }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.plus").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("Drop an audio or video file here").font(.headline)
            Text("Voice memos, MP3, WAV, M4A, MOV and MP4.").foregroundStyle(.secondary)
            Button("Choose File…") { choose() }.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.4))
        )
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.prompt = "Transcribe"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        transcribe(url)
    }

    private func transcribe(_ url: URL) {
        let name = url.lastPathComponent
        phase = .working(name)
        Task {
            do {
                let text = try await controller.transcribeFile(url)
                phase = .done(name: name, text: text)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func save(_ text: String, name: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = (name as NSString).deletingPathExtension + ".txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
