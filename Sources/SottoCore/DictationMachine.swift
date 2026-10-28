import Foundation

/// Push-to-talk state machine.
///
/// Transitions are synchronous and side-effect free: an event goes in, effects
/// come out, and the app performs them and feeds their results back as events.
/// Every recording gets a session number; results tagged with an old session
/// are dropped, so a late transcription can never paste into a newer dictation.
///
/// Hold the key to talk and release to insert. A short tap (shorter than
/// `tapThreshold`) latches recording on for hands-free dictation; the next
/// press ends it.
public struct DictationMachine: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case recording(session: Int, pressedAt: TimeInterval, latched: Bool)
        case transcribing(session: Int)
    }

    public enum Event: Equatable, Sendable {
        case hotkeyDown(at: TimeInterval)
        case hotkeyUp(at: TimeInterval)
        /// Another key went down while the hotkey was held: the user is typing a
        /// character with the modifier (e.g. Option+Q), not dictating.
        case chord
        case cancel
        case transcribed(session: Int, text: String)
        case failed(session: Int, message: String)
    }

    public enum Effect: Equatable, Sendable {
        case startCapture(session: Int)
        case stopCaptureAndTranscribe(session: Int)
        case discardCapture(session: Int)
        case insert(text: String, session: Int)
        case reportEmpty(session: Int)
        case reportFailure(message: String, session: Int)
    }

    public private(set) var phase: Phase = .idle
    public let tapThreshold: TimeInterval
    /// When false, a short tap is treated like any other release.
    public var latchOnTap: Bool
    private var lastSession = 0

    public init(tapThreshold: TimeInterval = 0.3, latchOnTap: Bool = true) {
        self.tapThreshold = tapThreshold
        self.latchOnTap = latchOnTap
    }

    public var currentSession: Int? {
        switch phase {
        case .idle: nil
        case .recording(let session, _, _), .transcribing(let session): session
        }
    }

    public mutating func handle(_ event: Event) -> [Effect] {
        switch (phase, event) {
        case (.idle, .hotkeyDown(let time)):
            lastSession += 1
            phase = .recording(session: lastSession, pressedAt: time, latched: false)
            return [.startCapture(session: lastSession)]

        case (.recording(let session, let pressedAt, false), .hotkeyUp(let time)):
            if latchOnTap, time - pressedAt < tapThreshold {
                phase = .recording(session: session, pressedAt: pressedAt, latched: true)
                return []
            }
            phase = .transcribing(session: session)
            return [.stopCaptureAndTranscribe(session: session)]

        case (.recording(let session, _, true), .hotkeyDown):
            phase = .transcribing(session: session)
            return [.stopCaptureAndTranscribe(session: session)]

        case (.recording(let session, _, false), .chord),
             (.recording(let session, _, _), .cancel):
            phase = .idle
            return [.discardCapture(session: session)]

        case (.recording(let session, _, _), .failed(let failed, let message)) where failed == session:
            phase = .idle
            return [.discardCapture(session: session), .reportFailure(message: message, session: session)]

        case (.transcribing, .cancel):
            // The pending result arrives with a stale session and is dropped.
            phase = .idle
            return []

        case (.transcribing(let session), .transcribed(let result, let text)) where result == session:
            phase = .idle
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? [.reportEmpty(session: session)]
                : [.insert(text: trimmed, session: session)]

        case (.transcribing(let session), .failed(let failed, let message)) where failed == session:
            phase = .idle
            return [.reportFailure(message: message, session: session)]

        default:
            // Key-up after a latched stop, presses while transcribing, stale
            // results, chords while latched: nothing to do.
            return []
        }
    }
}
