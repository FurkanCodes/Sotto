import Testing
@testable import SottoCore

struct DictationMachineTests {
    @Test func holdThenReleaseTranscribes() {
        var machine = DictationMachine()
        #expect(machine.handle(.hotkeyDown(at: 0)) == [.startCapture(session: 1)])
        #expect(machine.handle(.hotkeyUp(at: 1.0)) == [.stopCaptureAndTranscribe(session: 1)])
        #expect(machine.handle(.transcribed(session: 1, text: " Hello there. ")) == [.insert(text: "Hello there.", session: 1)])
        #expect(machine.phase == .idle)
    }

    @Test func shortTapLatchesUntilNextPress() {
        var machine = DictationMachine()
        _ = machine.handle(.hotkeyDown(at: 0))
        #expect(machine.handle(.hotkeyUp(at: 0.1)).isEmpty)
        #expect(machine.phase == .recording(session: 1, pressedAt: 0, latched: true))
        #expect(machine.handle(.hotkeyDown(at: 5)) == [.stopCaptureAndTranscribe(session: 1)])
        // The key-up that follows the stopping press does nothing.
        #expect(machine.handle(.hotkeyUp(at: 5.1)).isEmpty)
        #expect(machine.phase == .transcribing(session: 1))
    }

    @Test func chordWhileHoldingDiscards() {
        var machine = DictationMachine()
        _ = machine.handle(.hotkeyDown(at: 0))
        #expect(machine.handle(.chord) == [.discardCapture(session: 1)])
        #expect(machine.phase == .idle)
    }

    @Test func chordWhileLatchedIsIgnored() {
        var machine = DictationMachine()
        _ = machine.handle(.hotkeyDown(at: 0))
        _ = machine.handle(.hotkeyUp(at: 0.1))
        #expect(machine.handle(.chord).isEmpty)
        #expect(machine.currentSession == 1)
    }

    @Test func cancelWhileRecordingDiscards() {
        var machine = DictationMachine()
        _ = machine.handle(.hotkeyDown(at: 0))
        #expect(machine.handle(.cancel) == [.discardCapture(session: 1)])
        #expect(machine.phase == .idle)
    }

    @Test func cancelWhileTranscribingDropsLateResult() {
        var machine = DictationMachine()
        _ = machine.handle(.hotkeyDown(at: 0))
        _ = machine.handle(.hotkeyUp(at: 1))
        #expect(machine.handle(.cancel).isEmpty)
        #expect(machine.handle(.transcribed(session: 1, text: "late")).isEmpty)
    }

    @Test func staleResultNeverInsertsIntoNewSession() {
        var machine = DictationMachine()
        _ = machine.handle(.hotkeyDown(at: 0))
        _ = machine.handle(.hotkeyUp(at: 1))
        _ = machine.handle(.cancel)
        _ = machine.handle(.hotkeyDown(at: 2))
        _ = machine.handle(.hotkeyUp(at: 3))
        #expect(machine.handle(.transcribed(session: 1, text: "old")).isEmpty)
        #expect(machine.handle(.transcribed(session: 2, text: "new")) == [.insert(text: "new", session: 2)])
    }

    @Test func emptyTranscriptIsReported() {
        var machine = DictationMachine()
        _ = machine.handle(.hotkeyDown(at: 0))
        _ = machine.handle(.hotkeyUp(at: 1))
        #expect(machine.handle(.transcribed(session: 1, text: "  ")) == [.reportEmpty(session: 1)])
    }

    @Test func captureFailureWhileRecordingReportsAndResets() {
        var machine = DictationMachine()
        _ = machine.handle(.hotkeyDown(at: 0))
        #expect(machine.handle(.failed(session: 1, message: "No microphone")) == [
            .discardCapture(session: 1),
            .reportFailure(message: "No microphone", session: 1),
        ])
        #expect(machine.phase == .idle)
    }

    @Test func pressWhileTranscribingIsIgnored() {
        var machine = DictationMachine()
        _ = machine.handle(.hotkeyDown(at: 0))
        _ = machine.handle(.hotkeyUp(at: 1))
        #expect(machine.handle(.hotkeyDown(at: 1.05)).isEmpty)
        #expect(machine.phase == .transcribing(session: 1))
    }
}
