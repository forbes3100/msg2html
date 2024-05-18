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

let debug = 0
var haveLinks: Bool = false
var attDirUrl: URL?
var extAttFiles: [String: URL]?
var css: CSS?

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
    margin-top: 20px;
    margin-bottom: 0px;
    margin-left: 400px;
    margin-right: 10px;
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
    margin-top: 5px;
    margin-right: 300px;
}
.cm  {
    margin-top: 0px;
    margin-left: 250px;
    margin-right: 10px;
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
    margin-left: auto;
}
.n   {
    background-color: #ffffff;
    color: #505050;
    font-size: 70%;
    margin-top: 0px;
    margin-bottom: 0px;
    margin-left: 40px;
}
p    {
    background-color: #e6e6e6;
    border-radius: 15px;
    font-size: 80%;
    color: #000000;
    font-family: verdana;
    padding: 5px;
    width: fit-content;
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
    var who: String?
    var rowid: Int
    var date: Date
    var guid: String
    var isFromMe: Bool
    var hasAttach: Bool
    var handleID: Int
    var text: String?
    var svc: String

    init() {
        self.who = ""
        self.rowid = -1
        self.date = Date()
        self.guid = ""
        self.isFromMe = false
        self.hasAttach = false
        self.handleID = -1
        self.text = nil
        self.svc = ""
    }

    init(who: String?, rowid: Int, date: Date, guid: String, isFromMe: Bool, hasAttach: Bool,
         handleID: Int, text: String?, svc: String) {
        self.who = who
        self.rowid = rowid
        self.date = date
        self.guid = guid
        self.isFromMe = isFromMe
        self.hasAttach = hasAttach
        self.handleID = handleID
        self.text = text
        self.svc = svc
    }
}

class HTML {
    private var html = ""

    func append(tag: String, attributes: [String: String] = [:], content: String? = nil) {
        let a = attributes.map { " \($0.key)=\"\($0.value)\"" }.joined()
        let c = content ?? ""
        html.append("<\(tag)\(a)>\(c)</\(tag)>")
    }

    func append(body: String) {
        append(tag: "body", content: body)
    }

    func appendMessages(archivePath: String? = nil, year: Int, msgsBakDirPath: String, extAttDir: String? = nil) {
        let fileManager = FileManager.default

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

        let handlesName = "chat_handles.json"
        let handlesPath = msgsBakDirPath + handlesName
        var idNamedHandles: [String:String] = [:]
        if fileManager.fileExists(atPath: handlesPath) {
            do {
                let url = URL(fileURLWithPath: handlesPath)
                let data = try Data(contentsOf: url)
                idNamedHandles = try JSONSerialization.jsonObject(with: data, options: []) as! [String: String]
            } catch {
                fatalError("Reading database handles file \(handlesPath)")
            }
        }

        var messages: [Message] = []
        if let archivePath = archivePath {
            let msgSrc = MessageSource_Archive(msgsBakDirPath: msgsBakDirPath,
                                               idNamedHandles: idNamedHandles)
            messages = msgSrc.getMessages(inArchive: archivePath, forYear: year)
        } else {
            let msgSrc = MessageSource_ChatDB(msgsBakDirPath: msgsBakDirPath, idNamedHandles: idNamedHandles)
            messages = msgSrc.getMessagesFor(year: year)
        }

        var prevDay = 0
        var prevWho: String? = nil

        for msg in messages {

            let calendar = Calendar.current
            if calendar.component(.year, from: msg.date) != year {
                continue
            }

            let day = calendar.ordinality(of: .day, in: .year, for: msg.date) ?? -1
            if day != prevDay {
                append(tag: "hr")
            }

            css = CSS(isFromMe: msg.isFromMe, svc: msg.svc)
            if msg.isFromMe {
                append(tag: "p", attributes: ["class": "d"], content: """
                           \(msg.date) - from me, \(msg.svc)
                           #\(msg.rowid)
                           """)
            } else {
                let who = msg.who
                append(tag: "p", attributes: ["class": "d"], content: """
                           \(msg.date) - from \(who ?? "Unknown"), \(msg.svc)
                           #\(msg.rowid)
                           """)
                if who != prevWho || day != prevDay {
                    append(tag: "p", attributes: ["class": "n"], content: who ?? "Unknown")
                    prevWho = who
                }
            }
            prevDay = day
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
            let out = try FileHandle(forWritingTo: fileURL)
            defer { out.closeFile() }

            out.write(htmlHead.data(using: .utf8)!)
            out.write(html.data(using: .utf8)!)
            out.write(htmlTail.data(using: .utf8)!)
        } catch {
            fatalError("Could not open \(file) for writing: \(error)")
        }
    }

}

func msg2html() {
    let fileManager = FileManager.default

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

    let archivePath = "/Users/scott/Documents/messages_archive"
    let archiveYear = 2019

    let html = HTML()
    //let year = Calendar.current.component(.year, from: Date())
    let year = archiveYear
    html.appendMessages(archivePath: archivePath, year: year, msgsBakDirPath: msgsBakDirPath)
    html.write(file: msgsBakDirPath + "\(year).html")
}

/*

// Create a (unique) symlink to imageFileH in the links dir.
func addLinkTo(imageFileHtml: String, mime_t: String) {
    if mime_t.prefix(5) == "image" {
        let imageFile = imageFileHtml.replacingOccurrences(of: "%23", with: "#")
        let imagePath = URL(fileURLWithPath: imageFile).standardizedFileURL.path

        if !FileManager.default.fileExists(atPath: imagePath) {
            return
        }

        let imageName = URL(fileURLWithPath: imageFile).lastPathComponent
        var link = URL(fileURLWithPath: links).appendingPathComponent(imageName)
        var seq = 0
        let linkName = link.deletingPathExtension().lastPathComponent
        let linkExt = link.pathExtension

        while FileManager.default.fileExists(atPath: link.path) {
            seq += 1
            link = URL(fileURLWithPath: links).appendingPathComponent("\(linkName)_\(seq).\(linkExt)")
        }

        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: imagePath))
    }
}

func output(text: String) {
    if let out = outFileHandle {
        if debug > 0 {
            let utext = text.unicodeScalars.map { String(format: "\\u{%X}", $0.value) }.joined()
            out.write("<p\(css.info_class)>text(\(text.count)) = \(utext)</p>\n")
        }

        if !text.isEmpty {
            let text = text.htmlEscaped().replacingOccurrences(of: "\n", with: "<br>")

            out.write(
                "<div\(css.con_class)><div\(css.flex_class)>\n"
                + "<p\(css.text_class)>\(text)</p>\n"
                + "</div></div>\n"
            )
        }
    }
}

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

*/
