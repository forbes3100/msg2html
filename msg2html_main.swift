//
//  msg2html_main.swift
//  macbak
//
//  Created by Scott Forbes on 5/23/24.
//

import Foundation
import ArgumentParser

struct ConvertMessagesToHTML: ParsableCommand {
    @Argument(help: "Start year")
    var startYear: String

    @Option(name: .shortAndLong, help: "End year")
    var endYear: String?

    @Option(name: .shortAndLong, help: "Debug level")
    var debug: Int?

    @Option(name: .shortAndLong, help: "External attachment library to search")
    var externalAttachmentLibrary: String?

    @Flag(name: .shortAndLong, help: "Generate attachment links")
    var generateAttachmentLinks: Int

    func run() {
        var extra = ""
        if debug != nil {
            extra += "_dbg"
        }
        if generateAttachmentLinks > 0 {
            let links = "links"
            try? FileManager.default.createDirectory(atPath: links, withIntermediateDirectories: true)
        }
        
        if let last = Int(endYear ?? startYear),
           let start = Int(startYear) {
            for year in start...last {
                convertMessages(from: "chat.db", attachments: "Attachments",
                                externalAttachmentLibrary: externalAttachmentLibrary,
                                forYear: year, toHtmlFile: "\(year)\(extra)")
            }
        }
    }
}
