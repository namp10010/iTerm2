import XCTest
@testable import iTerm2SharedARC

class NSStringControlCharacterTests: XCTestCase {

    // MARK: - stringByReplacingControlCharactersExceptNewlineWithCaretLetter

    func testExceptNewline_empty() {
        let actual = ("" as NSString).replacingControlCharactersExceptNewlineWithCaretLetter()
        XCTAssertEqual(actual, "")
    }

    func testExceptNewline_singleControlChar() {
        let input = NSString(format: "%c", 1)
        XCTAssertEqual(input.replacingControlCharactersExceptNewlineWithCaretLetter(), "^A")
    }

    func testExceptNewline_newlinePreserved() {
        let actual = ("\n" as NSString).replacingControlCharactersExceptNewlineWithCaretLetter()
        XCTAssertEqual(actual, "\n")
    }

    func testExceptNewline_del() {
        let input = NSString(format: "%c", 0x7f)
        XCTAssertEqual(input.replacingControlCharactersExceptNewlineWithCaretLetter(), "^?")
    }

    func testExceptNewline_tabReplacedNewlineKept() {
        let input = NSString(format: "%c\n", 0x09)
        XCTAssertEqual(input.replacingControlCharactersExceptNewlineWithCaretLetter(), "^I\n")
    }

    func testExceptNewline_mixedWithText() {
        let input = NSString(format: "hello%cworld\nfoo%cbar", 1, 2)
        XCTAssertEqual(input.replacingControlCharactersExceptNewlineWithCaretLetter(), "hello^Aworld\nfoo^Bbar")
    }

    func testExceptNewline_onlyNewlines() {
        let actual = ("\n\n\n" as NSString).replacingControlCharactersExceptNewlineWithCaretLetter()
        XCTAssertEqual(actual, "\n\n\n")
    }

    func testExceptNewline_adjacentControlAndNewline() {
        let input = NSString(format: "%c\n%c", 1, 2)
        XCTAssertEqual(input.replacingControlCharactersExceptNewlineWithCaretLetter(), "^A\n^B")
    }
}
