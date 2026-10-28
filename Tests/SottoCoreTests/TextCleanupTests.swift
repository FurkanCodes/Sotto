import Foundation
import Testing
@testable import SottoCore

struct TextCleanupCase: Decodable, CustomTestStringConvertible, Sendable {
    let input: String
    let expected: String
    let removeFillers: Bool?
    let english: Bool?

    var testDescription: String { input.isEmpty ? "(empty)" : input }

    static func load() throws -> [TextCleanupCase] {
        struct File: Decodable { let cases: [TextCleanupCase] }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/text-cleanup.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).cases
    }
}

struct TextCleanupTests {
    @Test(arguments: try TextCleanupCase.load())
    func sharedFixture(_ fixture: TextCleanupCase) {
        let output = TextCleanup.clean(
            fixture.input,
            removeFillers: fixture.removeFillers ?? true,
            english: fixture.english ?? true
        )
        #expect(output == fixture.expected)
    }
}
