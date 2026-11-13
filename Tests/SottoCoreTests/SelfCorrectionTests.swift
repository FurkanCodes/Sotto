import Foundation
import Testing
@testable import SottoCore

struct SelfCorrectionCase: Decodable, CustomTestStringConvertible, Sendable {
    let input: String
    let expected: String

    var testDescription: String { input }

    static func load() throws -> [SelfCorrectionCase] {
        struct File: Decodable { let cases: [SelfCorrectionCase] }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/self-correction.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).cases
    }
}

struct SelfCorrectionTests {
    @Test(arguments: try SelfCorrectionCase.load())
    func sharedFixture(_ fixture: SelfCorrectionCase) {
        #expect(SelfCorrection.apply(fixture.input) == fixture.expected)
    }
}
