//
//  Msg2HtmlTests.swift
//  macbak
//
//  Created by Scott Forbes on 5/18/24.
//

import XCTest

final class Msg2HtmlTests: XCTestCase {
    let year = 2024
    let debug = true
    var htmlName = ""
    var htmlFile = ""
    let heicJpeg = "TestAttachments/05/ef/at_0_1234_5678/HEART.jpeg"
    let msg1a = "Test message 1a."
    let msg1b = "After."
    let msg2 = "Test message 2."
    let msg3 = "Test message 3."

    override func setUpWithError() throws {
        // Called before each test method
        htmlName = "test_\(year)_\(true)"
        htmlFile = "test_\(year)_\(true).html"
        if FileManager.default.fileExists(atPath: htmlFile) {
            try FileManager.default.removeItem(atPath: htmlFile)
        }
        if FileManager.default.fileExists(atPath: heicJpeg) {
            try FileManager.default.removeItem(atPath: heicJpeg)
        }
    }

    func testConvertOneYear() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: htmlFile))
        XCTAssertFalse(FileManager.default.fileExists(atPath: heicJpeg))

        let htmlDir = ""
        let archiveDir = "TestArchive"
        let attDir = "TestAttachments"
        let extAttDir: String? = nil

        convertMessages(from: archiveDir, htmlDir: htmlDir, attachments: attDir, externalAttachmentLibrary: extAttDir, forYear: year, toHtmlFile: htmlName)
        let htmlFileURL = URL(fileURLWithPath: htmlFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: htmlFileURL.path))

        let text = try String(contentsOfFile: htmlFile, encoding: .utf8)

        XCTAssertTrue(text.contains("<html>\n<head>\n<style>"))
        XCTAssertTrue(text.contains("</body>\n</html>"))

        XCTAssertTrue(text.contains(msg1a))
        XCTAssertTrue(text.contains(msg1b))
        XCTAssertTrue(text.contains(msg2))
        XCTAssertTrue(text.contains(msg3))

        let indexMsg1a = text.range(of: msg1a)?.lowerBound.utf16Offset(in: text) ?? -1
        let indexMsg1b = text.range(of: msg1b)?.lowerBound.utf16Offset(in: text) ?? -1
        let indexMsg2 = text.range(of: msg2)?.lowerBound.utf16Offset(in: text) ?? -1

        XCTAssertTrue(indexMsg1a < indexMsg1b)
        XCTAssertTrue(indexMsg1b < indexMsg2)
    }
}
