import XCTest
@testable import KeelhavenCore

/// A pipe delivers bytes in whatever pieces the kernel has, so the cuts fall
/// anywhere. These pin that a line comes out whole, once, however it was
/// sliced on the way in.
final class LineBufferTests: XCTestCase {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    func testCompleteLinesComeOutAsTheyArrive() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(data("one\ntwo\n")), ["one", "two"])
        XCTAssertEqual(buffer.append(data("three\n")), ["three"])
        XCTAssertEqual(buffer.finish(), [])
    }

    /// The ordinary case for a busy pipe: a chunk ends mid-line, and the rest
    /// of the line is the start of the next one.
    func testALineCutAcrossChunksIsHeldUntilItsNewlineArrives() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(data(#"{"message_type":"sta"#)), [])
        XCTAssertEqual(buffer.append(data(#"tus","percent"#)), [])
        XCTAssertEqual(buffer.append(data("_done\":0.5}\nnext")), [#"{"message_type":"status","percent_done":0.5}"#])
        XCTAssertEqual(buffer.append(data("\n")), ["next"])
    }

    /// A cut can land inside a character. Decoding the halves separately
    /// would turn a file name into replacement characters; holding the bytes
    /// until the line is complete keeps it intact.
    func testACharacterCutAcrossChunksSurvives() {
        let line = data("文档 名.txt\n")
        var buffer = LineBuffer()
        // One byte into the three-byte encoding of 文.
        XCTAssertEqual(buffer.append(line.prefix(1)), [])
        XCTAssertEqual(buffer.append(line.dropFirst(1)), ["文档 名.txt"])
    }

    func testEmptyLinesAreLinesToo() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(data("a\n\nb\n")), ["a", "", "b"])
    }

    /// A process that exits without a final newline has still said its last
    /// line.
    func testAnUnterminatedLastLineIsHandedOverAtTheEnd() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(data("done\nlast words")), ["done"])
        XCTAssertEqual(buffer.finish(), ["last words"])
        XCTAssertEqual(buffer.finish(), [], "and only once")
    }
}
