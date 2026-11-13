import Foundation
import Testing
@testable import SottoCore

struct StyleCase: Decodable, CustomTestStringConvertible, Sendable {
    let input: String
    let style: TextStyle
    let keep: [String]?
    let expected: String

    var testDescription: String { "\(style.rawValue): \(input)" }

    static func load() throws -> [StyleCase] {
        struct File: Decodable { let cases: [StyleCase] }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/styles.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).cases
    }
}

struct StylesTests {
    @Test(arguments: try StyleCase.load())
    func sharedFixture(_ fixture: StyleCase) {
        #expect(Styles.apply(fixture.input, style: fixture.style, keepCapitalized: fixture.keep ?? []) == fixture.expected)
    }

    @Test func defaultsByApp() {
        #expect(Styles.style(forBundleID: "com.tinyspeck.slackmacgap", rules: []) == .casual)
        #expect(Styles.style(forBundleID: "com.apple.Terminal", rules: []) == .plain)
        #expect(Styles.style(forBundleID: "com.jetbrains.intellij", rules: []) == .plain)
        #expect(Styles.style(forBundleID: "com.apple.mail", rules: []) == .standard)
        #expect(Styles.style(forBundleID: nil, rules: []) == .standard)
    }

    @Test func userRuleWins() {
        let slack = AppRef(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
        #expect(Styles.style(forBundleID: slack.bundleID, rules: [StyleRule(app: slack, style: .standard)]) == .standard)
    }

    @Test func onlyPlainDropsTheTrailingSpace() {
        #expect(TextStyle.plain.appendsSpace == false)
        #expect(TextStyle.casual.appendsSpace)
        #expect(TextStyle.standard.appendsSpace)
    }
}
