import XCTest
@testable import Paste

final class ContentTypeDetectorTests: XCTestCase {
    func testDetectsLinks() {
        XCTAssertEqual(ContentTypeDetector.detect(from: "https://example.com/path"), .link)
        XCTAssertEqual(ContentTypeDetector.detect(from: "www.apple.com"), .link)
    }

    func testDetectsColors() {
        XCTAssertEqual(ContentTypeDetector.detect(from: "#0F766E"), .color)
        XCTAssertEqual(ContentTypeDetector.detect(from: "#fff"), .color)
    }

    func testDetectsCode() {
        let sample = """
        import Foundation
        func greet(_ name: String) {
            print(name)
        }
        """
        XCTAssertEqual(ContentTypeDetector.detect(from: sample), .code)
    }

    func testDetectsPlainText() {
        XCTAssertEqual(ContentTypeDetector.detect(from: "你好，Paste"), .text)
    }

    func testPreviewTitleClipsLongLines() {
        let long = String(repeating: "a", count: 100)
        let title = ContentTypeDetector.previewTitle(for: long, type: .text)
        XCTAssertTrue(title.hasSuffix("…"))
        XCTAssertEqual(title.count, 78)
    }
}
