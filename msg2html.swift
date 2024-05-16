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
import SQLite3

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
    var rowid: Int
    var date: Date
    var guid: String
    var isFromMe: Bool
    var hasAttach: Bool
    var handleID: Int
    var text: String?
    var svc: String

    init(rowid: Int, date: Date, guid: String, isFromMe: Bool, hasAttach: Bool,
         handleID: Int, text: String?, svc: String) {
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

func getChatDBCopyPath(toDir msgsBakDirPath: String) -> String {
    let fileManager = FileManager.default
    let homeDir = fileManager.homeDirectoryForCurrentUser
    let originalFilePath = homeDir.appendingPathComponent("Library/Messages/chat.db").path
    let copyFilePath = msgsBakDirPath + "chat_copy.db"

    // Check if the copy file already exists and has the same modification date as the original file
    if fileManager.fileExists(atPath: copyFilePath) {
        do {
            let originalAttributes = try fileManager.attributesOfItem(atPath: originalFilePath)
            let copyAttributes = try fileManager.attributesOfItem(atPath: copyFilePath)
            let originalModificationDate = originalAttributes[.modificationDate] as! Date
            let copyModificationDate = copyAttributes[.modificationDate] as! Date
            if originalModificationDate == copyModificationDate {
                return copyFilePath
            }
        } catch {
            fatalError("Failed to get file attributes: \(error)")
        }
    }

    // remove any existing copy of the file
    try? fileManager.removeItem(atPath: copyFilePath)

    // attempt to copy the file to the Documents directory
    do {
        try fileManager.copyItem(atPath: originalFilePath, toPath: copyFilePath)

        // set read permissions on the copied file
        let fileAttributes = [FileAttributeKey.posixPermissions: NSNumber(value: 0o644)]
        try fileManager.setAttributes(fileAttributes, ofItemAtPath: copyFilePath)

        return copyFilePath
    } catch {
        fatalError("Failed to create chat database copy: \(error)")
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

    func appendMessagesFor(year: Int, msgsBakDirPath: String, extAttDir: String? = nil) {
        let fileManager = FileManager.default
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

        let chatDBFilePath = getChatDBCopyPath(toDir: msgsBakDirPath)
        var db: OpaquePointer?

        guard sqlite3_open_v2(chatDBFilePath, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            fatalError("Opening database \(chatDBFilePath): \(errorMessage)")
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let query = "SELECT rowid, id FROM handle;"
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            defer { sqlite3_finalize(statement) }

            var handles = [Int: String]()
            while sqlite3_step(statement) == SQLITE_ROW {
                let rowid = Int(sqlite3_column_int(statement, 0))
                let id = String(cString: sqlite3_column_text(statement, 1))
                handles[rowid] = idNamedHandles[id, default: id]
            }

            let messageQuery = """
            SELECT rowid, datetime(substr(date, 1, 9) + 978307200, 'unixepoch',
            'localtime') AS f_date, guid, is_from_me, cache_has_attachments,
            handle_id, text, service
            FROM message ORDER BY f_date;
            """
            var statement2: OpaquePointer?
            if sqlite3_prepare_v2(db, messageQuery, -1, &statement2,
                                  nil) == SQLITE_OK {
                defer { sqlite3_finalize(statement2) }

                var prevDay = 0
                var prevWho: String? = nil

                while sqlite3_step(statement2) == SQLITE_ROW {
                    let rowid = Int(sqlite3_column_int(statement2, 0))
                    let dateString = String(cString: sqlite3_column_text(statement2, 1))
                    let guid = String(cString: sqlite3_column_text(statement2, 2))
                    let isFromMe = sqlite3_column_int(statement2, 3) == 1
                    let hasAttach = sqlite3_column_int(statement2, 4) == 1
                    let handleId = Int(sqlite3_column_int(statement2, 5))
                    var text: String? = nil
                    if let t = sqlite3_column_text(statement2, 6) {
                        text = String(cString: t)
                    }
                    let svc = String(cString: sqlite3_column_text(statement2, 7))

                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    let date = dateFormatter.date(from: dateString)!

                    let msg = Message(
                        rowid: rowid,
                        date: date,
                        guid: guid,
                        isFromMe: isFromMe,
                        hasAttach: hasAttach,
                        handleID: handleId,
                        text: text,
                        svc: svc
                    )

                    let calendar = Calendar.current
                    if calendar.component(.year, from: date) != year {
                        continue
                    }

                    if msg.handleID == 0 {
                        msg.isFromMe = true
                    }

                    let day = calendar.ordinality(of: .day, in: .year, for: date) ?? -1
                    if day != prevDay {
                        append(tag: "hr")
                    }

                    let who = handles[msg.handleID]
                    css = CSS(isFromMe: msg.isFromMe, svc: msg.svc)
                    if msg.isFromMe {
                        append(tag: "p", attributes: ["class": "d"], content: """
                                   \(msg.date) - from me, \(msg.svc)
                                   #\(msg.rowid)
                                   """)
                    } else {
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

    let h = HTML()
    let year = Calendar.current.component(.year, from: Date())
    h.appendMessagesFor(year: year, msgsBakDirPath: msgsBakDirPath)
    h.write(file: msgsBakDirPath + "\(year).html")
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
