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
//import UniformTypeIdentifiers

// debug level: 0=none, 1=file, 2=message, 3=character, 4=attachment
var debug = 0

var haveLinks: Bool = false
var attDirUrl: URL?
var extAttFiles: [String: URL]?
let replaceObjToken = "\u{fffc}"

extension String {
    func htmlEscaped() -> String {
        var result = self
        let escapeMapping: [Character: String] = [
            "<": "&lt;",
            ">": "&gt;",
            "&": "&amp;",
            //"\"": "&quot;",
            //"'": "&#39;",
        ]

        for (key, value) in escapeMapping {
            result = result.replacingOccurrences(of: String(key), with: value)
        }

        return result
    }

    // Encode non-ASCII characters as XML character references
    func xmlCharRefReplace() -> String {
        var encodedString = ""
        for scalar in self.unicodeScalars {
            if scalar.isASCII {
                encodedString.append(Character(scalar))
            } else {
                encodedString.append("&#\(scalar.value);")
            }
        }
        return encodedString
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
    background-color: white;
    color: dimgray;
    font-size: 70%;
    margin-top: 3px;
    margin-bottom: 0px;
    text-align: center;
}
.i   {
    background-color: white;
    color: dimgray;
    font-size: 70%;
    font-style: italic;
    margin-top: 0px;
    margin-bottom: 0px;
    margin-left: 250px;
    margin-right: 10px;
}
.j   {
    background-color: white;
    color: dimgray;
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
    align-items: center;
    margin-top: 1px;
    margin-left: 250px;
    margin-right: 10px;
    text-align: right;
}
.me  {
    background-color: #4c86f8; /* blue */
    color: white;
    font-size: 80%;
    font-family: verdana;
    width: fit-content;
    margin-left: auto;
    text-align: left;
}
.g   {
    background-color: #5bc545; /* green */
    color: white;
    font-size: 80%;
    font-family: verdana;
    width: fit-content;
    margin-top: 1px;
    margin-bottom: 0px;
    margin-left: auto;
    text-align: left;
}
.n   {
    background-color: white;
    color: gray;
    font-size: 70%;
    margin-top: 5px;
    margin-bottom: 0px;
    padding-top: 1px;
    padding-bottom: 1px;
    margin-left: 0px;
}
.top   {
    background-color: white;
    color: darkblue;
    font-size: 70%;
    margin-top: 0px;
    margin-bottom: 0px;
    padding-top: 1px;
    padding-bottom: 1px;
    margin-left: 0px;
}
p    {
    background-color: #e5e5ea; /* very light gray */
    border-radius: 15px;
    font-size: 80%;
    color: black;
    font-family: verdana;
    padding: 4px;
    width: fit-content;
    margin-top: 2px;
    margin-bottom: 2px;
}
.hr_thread {
    margin-top: 60px;
}
.hr_day {
    border: none;
    height: 1px;
    background-color: lightgray;
    margin: 20px 0;
}
.nofile {
    background-color: white;
    border: 2px solid gray;
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

struct Message {
    var fileName: String
    var who: String?
    var threadID: String
    var rowid: Int
    var date: Date
    var guid: String
    var isFirst: Bool
    var isFromMe: Bool
    var text: String?
    var svc: String
    var party: String
    var attachments: [(String, URL?)]
}

func getMessagesByYear(source: String, msgsDirURL: URL, attachments: String,
                       extAttachments: String? = nil) -> [Int: [Message]] {
    let attachmentsURL = msgsDirURL.appendingPathComponent(attachments)

    var messagesByYear: [Int: [Message]] = [:]
    if source.hasSuffix("db") {
        /*
         let fileManager = FileManager.default
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
        messagesByYear = msgSrc.getMessagesByYear(inArchive: source,
            attachmentsURL: attachmentsURL, extAttachments: extAttachments)
    }
    return messagesByYear
}


class HTML {
    private var html = ""
    var css: CSS?
    var links: String? = nil
    var basePathCount: Int

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
        //if let fileType = UTType(filenameExtension: fileURL.pathExtension) {
        //    mimeType = fileType.preferredMIMEType
        //} else {
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
        //}
        
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
        if debug > 1 {
            print("output(text: \"\(text)\")")
        }
        if let css = self.css {
            if debug > 2 {
                let utext = text.unicodeScalars.map { String(format: " \\u{%X}", $0.value) }.joined()
                html.append("<p\(css.info_class)>text(\(text.count)) = \(utext)</p>\n")
            }
            
            if !text.isEmpty {
                let text = text.htmlEscaped().xmlCharRefReplace()
                        .replacingOccurrences(of: "\n", with: "<br>")
                
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
        let (fileName, url) = msg.attachments[attachmentNo]
        guard let css = css else { return }
        if debug > 1 {
            print("output(attachmentNo: \(attachmentNo) for \(String(describing: msg.text))")
        }

        if let url = url, fileManager.fileExists(atPath: url.path) {
            let n = url.pathComponents.count - self.basePathCount
            var aPath = url.pathComponents.suffix(n).joined(separator: "/")
            let aWidth = 300
            let aSplitExt = (aPath as NSString).pathExtension
            let isPP = aSplitExt == "pluginPayloadAttachment"
            var (mimeT, aDate) = getMimeTypeAndDate(for: url)

            if debug > 3 {
                html.append("<p\(css.info_class)>attFileURL=\(aPath)</p>\n")
                let mimeTStr = String(describing: mimeT)
                let dateStr = String(describing: aDate)
                html.append("<p\(css.info_class)>a_path=\(aPath), \(mimeTStr), \(dateStr)</p>\n")
            } else {
                if debug > 2 {
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
                    if debug > 3 {
                        let mimeTStr = String(describing: mimeT)
                        let dateStr = String(describing: aDate)
                        html.append("<p\(css.info_class)>\(aPath), \(mimeTStr), \(dateStr)</p>\n")
                    }
                }

                guard let aPathEncoded = aPath.addingPercentEncoding(
                    withAllowedCharacters: .urlPathAllowed) else {
                    fatalError("Can't encode filename \"\(aPath)\"")
                }
                html.append(
                    "<div\(css.con_class)><div\(css.flex_class)>\n"
                    + "<img\(css.img_class) src=\"\(aPathEncoded)\" width=\"\(aWidth)\">\n"
                    + "</div></div>\n"
                )

                if (links != nil) && !msg.isFromMe {
                    addLinkTo(imageFileHtml: aPath, mime_t: mimeT!)
                }
            }
        } else {
            var name = fileName
            if let url = url {
                name = url.path
            }
            html.append("<p class=\"nofile\">Missing file \"\(name)\"</p>\n")
        }
    }

    init(messages: [Message], baseURL: URL) {
        self.basePathCount = baseURL.pathComponents.count
        var prevDay = 0
        var prevWho: String? = nil
        var prevMessage: Message? = nil

        if debug > 0 {
            print("Building HTML")
        }
        var isFirstMessageinHtmlFile = true
        for msg in messages {
            
            if let p = prevMessage,
               p.date == msg.date && p.text == msg.text && p.who == msg.who {
                continue
            }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "M/d/yy, h:mm a"
            let dateStr = dateFormatter.string(from: msg.date)
            
            if debug > 1 {
                print("\n message(file: \(msg.fileName)\n    who: \(msg.who ?? "?")")
            }
            let calendar = Calendar.current
            
            let isNewThread = msg.isFirst || msg.party != prevMessage?.party
            let day = calendar.ordinality(of: .day, in: .year, for: msg.date) ?? -1
            if (day != prevDay || isNewThread) && !isFirstMessageinHtmlFile  {
                if isNewThread {
                    html.append("<hr class=\"hr_thread\">\n")
                } else {
                    html.append("<hr class=\"hr_day\">\n")
                }
            }
            
            css = CSS(isFromMe: msg.isFromMe, svc: msg.svc)
            let who = msg.who ?? "Unknown"
            if msg.isFromMe {
                if debug > 2 {
                    append(tag: "p", attributes: ["class": "d"], content: """
                               \(msg.date) - from me, \(msg.svc)
                               #\(msg.rowid)
                               """)
                }
            } else {
                if debug > 2 {
                    append(tag: "p", attributes: ["class": "d"], content: """
                               \(msg.date) - from \(who), \(msg.svc)
                               #\(msg.rowid)
                               """)
                }
            }
            if who != prevWho || day != prevDay {
                html.append(
                    "<div style=\"display: flex; flex-direction: column; align-items: center\">\n")
                if isNewThread {
                    let threadID = msg.threadID.htmlEscaped().xmlCharRefReplace()
                    let party = msg.party.htmlEscaped().xmlCharRefReplace()
                    html.append("<p class=\"top\">\(msg.svc) with \(threadID) (\(party))</p>")
                }
                html.append("<p class=\"top\">\(dateStr)</p></div>\n")
            }
            if !msg.isFromMe {
                let whoEncoded = who.htmlEscaped().xmlCharRefReplace()
                append(tag: "p", attributes: ["class": "n"], content: whoEncoded)
            }
            prevWho = who
            prevDay = day
            prevMessage = msg
            isFirstMessageinHtmlFile = false
            
            // Possible cases:
            //   text
            //   attachment
            //   text 0, attachment 0, [text 1, attachment 1, ...] text n
            if let text = msg.text {
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
            if debug > 0 {
                print("Writing \(fileURL.path)")
            }
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

/// Convert messages in database db to an HTML file.
///
/// - Parameters:
///   - from: Database file or archive directory path string.
///   - msgsDir: Directory path string, containing attachments directory, where HTML file(s) are to be written.
///   - attachments: Attachments directory name.
///   - extAttachments: Optional external attachments directory for additional attachments.
///   - year: Starting year as an integer.
///   - toYear: Optional ending year as an integer.
///   - toHtmlFile: Output file base name.
func convertMessages(from source: String, msgsDir: String, attachments: String,
                     extAttachments: String? = nil,
                     year: Int, toYear: Int? = nil, toHtmlFile: String) {
    
    // convert all messages in database
    let msgsDirURL = URL(fileURLWithPath: msgsDir)
    let messagesByYear = getMessagesByYear(source: source, msgsDirURL: msgsDirURL,
            attachments: attachments, extAttachments: extAttachments)

    for y in year...(toYear ?? year) {
        if let messagesUnsorted = messagesByYear[y] {
            let messages = messagesUnsorted.sorted { $0.date < $1.date }
            let html = HTML(messages: messages, baseURL: msgsDirURL)
            let name = msgsDirURL.appendingPathComponent(toHtmlFile + "\(y).html").path
            html.write(file: name)
        }
    }
}
