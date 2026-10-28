import Foundation
import Testing
@testable import SottoCore

struct CorrectionLearningCase: Decodable, CustomTestStringConvertible, Sendable {
    let before: String
    let after: String
    let inserted: String
    let known: [String]?
    let expected: String?

    var testDescription: String { "\(before) → \(after)" }

    static func load() throws -> [CorrectionLearningCase] {
        struct File: Decodable { let cases: [CorrectionLearningCase] }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/correction-learning.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).cases
    }
}

struct CorrectionLearningTests {
    @Test(arguments: try CorrectionLearningCase.load())
    func sharedFixture(_ fixture: CorrectionLearningCase) {
        let learned = CorrectionLearning.learnedWord(
            before: fixture.before, after: fixture.after, inserted: fixture.inserted, known: fixture.known ?? []
        )
        #expect(learned == fixture.expected)
    }
}
