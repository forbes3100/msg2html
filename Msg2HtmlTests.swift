//
//  Msg2HtmlTests.swift
//  macbak
//
//  Created by Scott Forbes on 5/18/24.
//

import XCTest

final class Msg2HtmlTests: XCTestCase {
    let year = 2021
    let debug = true
    let htmlName = "test_\(2021)_\(true)"
    let htmlFile = "test_\(2021)_\(true).html"
    let heicJpeg = "path/to/heic_jpeg_file.jpg" // Replace with actual path if needed

    let msg1a = "Message 1a text"
    let msg1b = "Message 1b text"
    let msg2 = "Message 2 text"
    let msg3 = "Message 3 text"

    override func setUpWithError() throws {
        // Called before each test method
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
/*
        let dbName = "path/to/db_name" // Replace with actual path
        let attDir = "path/to/att_dir" // Replace with actual path
        let extAttDir: String? = nil
        
        // Assuming msg2html has a method convert() similar to the Python version
        //try msg2html.convert(dbName: dbName, attDir: attDir, year: year, extAttDir: extAttDir,
        //                     htmlName: htmlName, debug: debug)

        XCTAssertTrue(FileManager.default.fileExists(atPath: htmlFile))
        
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
 */
    }
}
