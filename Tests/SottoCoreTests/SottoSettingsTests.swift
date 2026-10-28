import Foundation
import Testing
@testable import SottoCore

struct SottoSettingsTests {
    @Test func roundTrips() throws {
        var settings = SottoSettings()
        settings.dictationKey = .fn
        settings.customWords = ["Furkan", "Sotto"]
        settings.microphoneUID = "BuiltInMicrophoneDevice"
        #expect(SottoSettings.decode(try settings.encoded()) == settings)
    }

    @Test func damagedFieldsFallBackOneByOne() {
        let json = #"{"dictationKey": "leftShift", "removeFillerWords": "yes", "showPill": false, "unloadAfterMinutes": -3}"#
        let settings = SottoSettings.decode(Data(json.utf8))
        #expect(settings.dictationKey == .rightOption)
        #expect(settings.removeFillerWords == true)
        #expect(settings.showPill == false)
        #expect(settings.unloadAfterMinutes == 0)
    }

    @Test func unreadableFileGivesDefaults() {
        #expect(SottoSettings.decode(Data("not json".utf8)) == SottoSettings())
    }

    @Test func unknownFieldsFromNewerVersionsAreIgnored() {
        let json = #"{"version": 7, "playSounds": true, "someFutureOption": 42}"#
        let settings = SottoSettings.decode(Data(json.utf8))
        #expect(settings.playSounds == true)
        #expect(settings.version == 7)
    }
}
