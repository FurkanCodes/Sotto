import Foundation
import Testing
@testable import SottoCore

struct CustomWordsCase: Decodable, CustomTestStringConvertible, Sendable {
    let input: String
    let words: [String]
    let threshold: Double
    let expected: String

    var testDescription: String { input }

    static func load() throws -> [CustomWordsCase] {
        struct File: Decodable { let cases: [CustomWordsCase] }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/custom-words.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).cases
    }
}

struct CustomWordsTests {
    @Test(arguments: try CustomWordsCase.load())
    func sharedFixture(_ fixture: CustomWordsCase) {
        #expect(CustomWords.apply(fixture.input, words: fixture.words, threshold: fixture.threshold) == fixture.expected)
    }

    @Test(arguments: [("Robert", "R163"), ("Rupert", "R163"), ("Ashcraft", "A261"), ("Tymczak", "T522"), ("Pfister", "P236")])
    func soundex(_ word: String, _ code: String) {
        #expect(CustomWords.soundex(word) == code)
    }

    @Test func levenshtein() {
        #expect(CustomWords.levenshtein("kitten", "sitting") == 3)
        #expect(CustomWords.levenshtein("", "abc") == 3)
    }
}
