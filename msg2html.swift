// msg2html -- Convert a Mac Messages database into HTML
//
// Copyright (C) 2023 Scott Forbes
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

import Foundation
import AppKit
import UniformTypeIdentifiers

let debug = 0
var haveLinks: Bool = false
var attDirUrl: URL?
var extAttFiles: [String: URL]?

extension String {
    func htmlEscaped() -> String {
        var result = self
        let escapeMapping: [Character: String] = [
            "<": "&lt;",
            ">": "&gt;",
            "&": "&amp;",
            "\"": "&quot;",
            "'": "&#x27;",
        ]

        for (key, value) in escapeMapping {
            result = result.replacingOccurrences(of: String(key), with: value)
        }

        return result
    }
}

// Common HTML head and foot, including CSS
// classes are: d=date, i=my_info, j=info, c=container, cm=my_container,
// me=my_text, g=my_sms_text, n=name, p=text

let htmlHead = """
<!DOCTYPE html>
<html>
<head>
<style>
.d   {
    background-color: #ffffff;
    color: #505050;
    font-size: 70%;
    margin-top: 3px;
    margin-bottom: 0px;
    text-align: center;
}
.i   {
    background-color: #ffffff;
    color: #505050;
    font-size: 70%;
    font-style: italic;
    margin-top: 0px;
    margin-bottom: 0px;
    margin-left: 250px;
    margin-right: 10px;
}
.j   {
    background-color: #ffffff;
    color: #505050;
    font-size: 70%;
    font-style: italic;
    margin-top: 0px;
    margin-bottom: 0px;
    margin-left: 0px;
    margin-right: 10px;
}
.c   {
    margin-top: 1px;
    margin-right: 300px;
}
.cm  {
    display: flex;
    justify-content: flex-end;
    align-items: center; /* Align items vertically if needed */
    margin-top: 1px;
    margin-left: 250px;
    margin-right: 10px;
    text-align: right;
}
.me  {
    background-color: #1b86fd;
    color: #ffffff;
    font-size: 80%;
    font-family: verdana;
    width: fit-content;
    margin-left: auto;
}
.g   {
    background-color: #2dbf4f;
    color: #ffffff;
    font-size: 80%;
    font-family: verdana;
    width: fit-content;
    margin-top: 1px;
    margin-bottom: 0px;
    margin-left: auto;
}
.n   {
    background-color: #ffffff;
    color: #505050;
    font-size: 70%;
    margin-top: 0px;
    margin-bottom: 0px;
    padding-top: 1px;
    padding-bottom: 1px;
    margin-left: 40px;
}
p    {
    background-color: #e6e6e6;
    border-radius: 15px;
    font-size: 80%;
    color: #000000;
    font-family: verdana;
    padding: 4px;
    width: fit-content;
    margin-top: 2px;
    margin-bottom: 2px;
}
</style>
</head>
<body>

"""

let htmlTail = """

</body>
</html>
"""


// Cascading Style Sheet classes, based on context
struct CSS {
    var con_class: String
    var flex_class: String
    var text_class: String
    var info_class: String
    var img_class: String

    init(isFromMe: Bool, svc: String) {
        if isFromMe {
            con_class = " class=\"cm\""
            flex_class = " style=\"display: flex; justify-content: flex-end\""
            let bubble = (svc == "SMS") ? "g" : "me"
            text_class = " class=\"\(bubble)\""
            info_class = " class=\"i\""
            img_class = " class=\"cm\""
        } else {
            con_class = " class=\"c\""
            flex_class = ""
            text_class = ""
            info_class = " class=\"j\""
            img_class = ""
        }
    }
}

class Message {
    var fileName: String
    var who: String?
    var rowid: Int
    var date: Date
    var guid: String
    var isFromMe: Bool
    var hasAttach: Bool
    var handleID: Int
    var text: String?
    var svc: String
    var attachments: [URL]

    init() {
        self.fileName = ""
        self.who = ""
        self.rowid = -1
        self.date = Date()
        self.guid = ""
        self.isFromMe = false
        self.hasAttach = false
        self.handleID = -1
        self.text = nil
        self.svc = ""
        self.attachments = []
    }

    init(fileName: String, who: String?, rowid: Int, date: Date, guid: String, isFromMe: Bool,
         hasAttach: Bool, handleID: Int, text: String?, svc: String, attachments: [URL]) {
        self.fileName = fileName
        self.who = who
        self.rowid = rowid
        self.date = date
        self.guid = guid
        self.isFromMe = isFromMe
        self.hasAttach = hasAttach
        self.handleID = handleID
        self.text = text
        self.svc = svc
        self.attachments = attachments
    }
}

class HTML {
    private var html = ""
    var css: CSS?
    var links: String? = nil

    func append(tag: String, attributes: [String: String] = [:], content: String? = nil) {
        let a = attributes.map { " \($0.key)=\"\($0.value)\"" }.joined()
        let c = content ?? ""
        html.append("<\(tag)\(a)>\(c)</\(tag)>")
    }

    func append(body: String) {
        append(tag: "body", content: body)
    }

    // Create a (unique) symlink to imageFileH in the links dir.
    func addLinkTo(imageFileHtml: String, mime_t: String) {
        if mime_t.prefix(5) == "image" {
            let imageFile = imageFileHtml.replacingOccurrences(of: "%23", with: "#")
            let imagePath = URL(fileURLWithPath: imageFile).standardizedFileURL.path

            if !FileManager.default.fileExists(atPath: imagePath) {
                return
            }

            let imageName = URL(fileURLWithPath: imageFile).lastPathComponent
            var link = URL(fileURLWithPath: links!).appendingPathComponent(imageName)
            var seq = 0
            let linkName = link.deletingPathExtension().lastPathComponent
            let linkExt = link.pathExtension

            while FileManager.default.fileExists(atPath: link.path) {
                seq += 1
                link = URL(fileURLWithPath: links!).appendingPathComponent(
                    "\(linkName)_\(seq).\(linkExt)")
            }

            try? FileManager.default.createSymbolicLink(at: link,
                                        withDestinationURL: URL(fileURLWithPath: imagePath))
        }
    }

    func getMimeTypeAndDate(for fileURL: URL) -> (mimeType: String?, fileDate: String?) {
        var mimeType: String? = nil
        var fileDate: String? = nil
        
        // Get the MIME type using UTType
        if let fileType = UTType(filenameExtension: fileURL.pathExtension) {
            mimeType = fileType.preferredMIMEType
        } else {
            // Fallback method to determine MIME type based on file extension
            switch fileURL.pathExtension.lowercased() {
            case "jpg", "jpeg":
                mimeType = "image/jpeg"
            case "png":
                mimeType = "image/png"
            case "gif":
                mimeType = "image/gif"
            case "heic":
                mimeType = "image/heic"
            case "m4a":
                mimeType = "audio/x-m4a"
            default:
                mimeType = "application/octet-stream"
            }
        }
        
        // Get the file modification date
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                fileDate = dateFormatter.string(from: modificationDate)
            }
        } catch {
            print("Error getting file attributes: \(error.localizedDescription)")
        }
        
        return (mimeType, fileDate)
    }

    /// Write text to output as HTML, converting emoji.
    func output(text: String) {
        print("output(text: \"\(text)\")")
        if let css = self.css {
            if debug > 0 {
                let utext = text.unicodeScalars.map { String(format: " \\u{%X}", $0.value) }.joined()
                html.append("<p\(css.info_class)>text(\(text.count)) = \(utext)</p>\n")
            }
            
            if !text.isEmpty {
                let text = text.htmlEscaped().replacingOccurrences(of: "\n", with: "<br>")
                
                html.append(
                    "<div\(css.con_class)><div\(css.flex_class)>\n"
                    + "<p\(css.text_class)>\(text)</p>\n"
                    + "</div></div>\n"
                )
            }
        }
    }

    /// Convert a message attachment to HTML.
    ///
    /// - Parameters:
    ///   - attachmentNo: attachment sequence number
    ///   - msg: Message
    func output(attachmentNo: Int, msg: Message) {
        let fileManager = FileManager.default
        let attFileURL = msg.attachments[attachmentNo]
        var aPath = attFileURL.pathComponents.suffix(5).joined(separator: "/")

        guard let css = css else { return }

        print("output(attachmentNo: \(attachmentNo) for \(String(describing: msg.text))")
        if debug > 1 {
            html.append("<p\(css.info_class)>attFileURL=\(aPath)</p>\n")
        }

        if fileManager.fileExists(atPath: attFileURL.path) {
            let aWidth = 300
            let aSplitExt = (aPath as NSString).pathExtension
            let isPP = aSplitExt == "pluginPayloadAttachment"
            var (mimeT, aDate) = getMimeTypeAndDate(for: attFileURL)

            if debug > 1 {
                let mimeTStr = String(describing: mimeT)
                let dateStr = String(describing: aDate)
                html.append("<p\(css.info_class)>a_path=\(aPath), \(mimeTStr), \(dateStr)</p>\n")
            } else {
                if debug > 0 {
                    html.append("<p\(css.info_class)>\(aPath)</p>\n")
                }
            }

            if let mimeType = mimeT, mimeType.hasPrefix("audio") {
                html.append("""
                <audio controls>
                <source src="\(aPath)" type="audio/x-m4a">
                Your browser does not support the audio tag.
                </audio>\n
                """)
            } else if !isPP {
                if mimeT == "image/heic" {
                    let jpegPath = (aPath as NSString).deletingPathExtension + ".jpeg"
                    let jpegURL = URL(fileURLWithPath: jpegPath)
                    
                    if !fileManager.fileExists(atPath: jpegPath) {
                        if let image = NSImage(contentsOfFile: aPath) {
                            if let tiffData = image.tiffRepresentation,
                               let bitmap = NSBitmapImageRep(data: tiffData),
                               let jpegData = bitmap.representation(using: .jpeg, properties: [:]) {
                                try? jpegData.write(to: jpegURL)
                            }
                        }
                    }
                    aPath = jpegPath
                    mimeT = "image/jpeg"
                    if debug > 1 {
                        let mimeTStr = String(describing: mimeT)
                        let dateStr = String(describing: aDate)
                        html.append("<p\(css.info_class)>\(aPath), \(mimeTStr), \(dateStr)</p>\n")
                    }
                }

                html.append(
                    "<div\(css.con_class)><div\(css.flex_class)>\n"
                    + "<img\(css.img_class) src=\"\(aPath)\" width=\"\(aWidth)\">\n"
                    + "</div></div>\n"
                )

                if (links != nil) && !msg.isFromMe {
                    addLinkTo(imageFileHtml: aPath, mime_t: mimeT!)
                }
            }
        } else {
            html.append("<p\(css.info_class)>Expected file! \(attFileURL.path)</p>\n")
        }
    }

    func appendMessages(source: String, htmlDirURL: URL, attachments: String, year: Int,
                        extAttDir: String? = nil) {
        let fileManager = FileManager.default
        let attachmentsURL = htmlDirURL.appendingPathComponent(attachments)

        if let extAttDir = extAttDir, fileManager.fileExists(atPath: extAttDir) {
            var files = [String]()
            let enumerator = fileManager.enumerator(atPath: extAttDir)
            while let element = enumerator?.nextObject() as? String {
                files.append(element)
            }
            extAttFiles = [String: URL]()
            for file in files {
                extAttFiles![file] = URL(fileURLWithPath: extAttDir)
            }
        }

        var messages: [Message] = []
        if source.hasSuffix("db") {
            /*
            let handlesName = "chat_handles.json"
            let handlesURL = URL(string: source)?.deletingLastPathComponent().appending(path: handlesName)
            var idNamedHandles: [String:String] = [:]
            if let url = handlesURL,
               fileManager.fileExists(atPath: handlesURL!.path) {
                do {
                    let data = try Data(contentsOf: url)
                    idNamedHandles = try JSONSerialization.jsonObject(with: data,
                                                                      options: []) as! [String: String]
                } catch {
                    fatalError("Reading database handles file \(url.path)")
                }
            }

            let msgSrc = MessageSource_ChatDB(msgsBakDirPath: msgsBakDirPath,
                                              idNamedHandles: idNamedHandles)
            messages = msgSrc.getMessagesFor(year: year)
             */
        } else {
            let msgSrc = MessageSource_Archive()
            messages = msgSrc.getMessages(inArchive: source, attachmentsURL: attachmentsURL, forYear: year)
        }

        var prevDay = 0
        var prevWho: String? = nil

        print("============== writing HTML ===============")
        for msg in messages {

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "M/d/yy, h:mm a"
            let dateStr = dateFormatter.string(from: msg.date)

            print("\n message(file: \(msg.fileName)\n    who: \(msg.who ?? "?")")
            let calendar = Calendar.current
            if calendar.component(.year, from: msg.date) != year {
                continue
            }

            let day = calendar.ordinality(of: .day, in: .year, for: msg.date) ?? -1
            if day != prevDay {
                append(tag: "hr")
            }

            css = CSS(isFromMe: msg.isFromMe, svc: msg.svc)
            let who = msg.who
            if msg.isFromMe {
                if debug > 0 {
                    append(tag: "p", attributes: ["class": "d"], content: """
                               \(msg.date) - from me, \(msg.svc)
                               #\(msg.rowid)
                               """)
                }
            } else {
                if debug > 0 {
                    append(tag: "p", attributes: ["class": "d"], content: """
                               \(msg.date) - from \(who ?? "Unknown"), \(msg.svc)
                               #\(msg.rowid)
                               """)
                }
            }
            if who != prevWho || day != prevDay {
                html.append(
                    "<div style=\"display: flex; flex-direction: column; align-items: center\">\n"
                    + "<p class=\"n\">\(msg.svc) with \(who ?? "Unknown")</p>"
                    + "<p class=\"n\">\(dateStr)</p>"
                    + "</div>\n"
                )
            }
            prevWho = who
            prevDay = day

            // Possible cases:
            //   text
            //   attachment
            //   text 0, attachment 0, [text 1, attachment 1, ...] text n
            if let text = msg.text {
                let replaceObjToken = "\u{fffc}"
                var i = text.startIndex
                var seq = 0
                
                while let range = text.range(of: replaceObjToken, range: i..<text.endIndex) {
                    let precedingText = String(text[i..<range.lowerBound])
                    output(text: precedingText)
                    i = range.upperBound
                    output(attachmentNo: seq, msg: msg)
                    seq += 1
                }
                
                // Output the remaining text after the last placeholder
                if i < text.endIndex {
                    let remainingText = String(text[i..<text.endIndex])
                    output(text: remainingText)
                }
            } else {
                output(attachmentNo: 0, msg: msg)
            }
        }
    }

    func write(file: String) {
        let fileURL = URL(fileURLWithPath: file)

        do {
            // Create the file if it doesn't exist
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
            }

            // Write the content to the file
            print("Writing \(fileURL.path)")
            let out = try FileHandle(forWritingTo: fileURL)
            defer { out.closeFile() }

            out.truncateFile(atOffset: 0)
            out.write(htmlHead.data(using: .utf8)!)
            out.write(html.data(using: .utf8)!)
            out.write(htmlTail.data(using: .utf8)!)
        } catch {
            fatalError("Could not open \(file) for writing: \(error)")
        }
    }

}

/// Convert one year of messages in database db to an HTML file.
///
/// - Parameters:
///   - from: Database file or archive directory path string.
///   - htmlDir: Directory path string, containing attachments directory, where HTML file is to be written.
///   - attachments: Attachments directory name.
///   - forYear: Desired year as an integer.
///   - externalAttachmentLibrary: Optional external attachments directory for additional attachments.
///   - toHtmlFile: Output file base name.
func convertMessages(from source: String, htmlDir: String, attachments: String,
                     externalAttachmentLibrary: String? = nil,
                     forYear year: Int, toHtmlFile: String) {
    
    // if external attachments directory path given, make a list of files there
    // ** TODO **
    
    // convert all messages in database
    let html = HTML()
    //let year = Calendar.current.component(.year, from: Date())
    let htmlDirURL = URL(fileURLWithPath: htmlDir)
    html.appendMessages(source: source, htmlDirURL: htmlDirURL, attachments: attachments, year: year)
    html.write(file: htmlDirURL.appendingPathComponent(toHtmlFile + ".html").path)
}

func msg2html() {

    /*
    let msgsBakName = "messages_icloud_bak"
    let docsPath = try? fileManager.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
    ).path + "/"
    let msgsBakDirPath = (docsPath ?? "") + msgsBakName + "/"

    if !(fileManager.fileExists(atPath: msgsBakDirPath)) {
        do {
            try fileManager.createDirectory(
                atPath: msgsBakDirPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            fatalError("Creating backup folder \(msgsBakDirPath)")
        }
    }
*/
    let fileManager = FileManager.default
    let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
    print("Current Directory: \(currentDirectoryURL.path)")
//    let archivePath = currentDirectoryURL.appendingPathComponent("TestArchive").path
//    let archiveAttachments = "TestAttachments"
//    let archiveYear = 2024
    let htmlDir = "/Volumes/SSD01A/msgs_from_archive"
    let archivePath = htmlDir + "/Archive"
    let archiveAttachments = "Attachments"
    let year = 2016

    convertMessages(from: archivePath, htmlDir: htmlDir, attachments: archiveAttachments,
                    forYear: year, toHtmlFile: "testOut\(year)")
}
