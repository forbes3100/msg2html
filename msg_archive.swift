// msg_archive -- Read from Mac ~/Library/Messages/Archive files
//
// Copyright (C) 2024 Scott Forbes
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

func indent(_ depth: Int) -> String {
    return String(repeating: "  ", count: depth)
}

enum FileError: Error {
    case fileNotFound
    case unsupportedFileType
    case databaseError(String)
    case xmlParsingError
}

import Foundation

class Presentity: NSObject, NSSecureCoding {
    var AccountID: String
    var AnonymousKey: Bool
    var ID: String
    var ServiceLoginID: String
    var ServiceName: String

    static var supportsSecureCoding: Bool {
        return true
    }

    required init?(coder: NSCoder) {
        // Initialize all properties with default values before calling super.init()
        self.AccountID = coder.decodeObject(forKey: "AccountID") as? String ?? ""
        self.AnonymousKey = coder.decodeBool(forKey: "AnonymousKey")
        self.ID = coder.decodeObject(forKey: "ID") as? String ?? ""
        self.ServiceLoginID = coder.decodeObject(forKey: "ServiceLoginID") as? String ?? ""
        self.ServiceName = coder.decodeObject(forKey: "ServiceName") as? String ?? ""

        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(AccountID, forKey: "AccountID")
        coder.encode(AnonymousKey, forKey: "AnonymousKey")
        coder.encode(ID, forKey: "ID")
        coder.encode(ServiceLoginID, forKey: "ServiceLoginID")
        coder.encode(ServiceName, forKey: "ServiceName")
    }

    override init() {
        // Initialize properties with default values
        self.AccountID = ""
        self.AnonymousKey = false
        self.ID = ""
        self.ServiceLoginID = ""
        self.ServiceName = ""

        super.init()
    }
}

import Foundation

class InstantMessage: NSObject, NSSecureCoding {
    var BaseWritingDirection: Int
    var Flags: Int
    var GUID: String
    var IsInvitation: Bool
    var IsRead: Bool
    var MessageText: NSMutableAttributedString
    var OriginalMessage: String
    var Sender: Presentity
    var Subject: Presentity
    var Time: NSDate

    static var supportsSecureCoding: Bool {
        return true
    }

    required init?(coder: NSCoder) {
        // Initialize all properties with default values before calling super.init()
        self.BaseWritingDirection = coder.decodeInteger(forKey: "BaseWritingDirection")
        self.Flags = coder.decodeInteger(forKey: "Flags")
        self.GUID = coder.decodeObject(forKey: "GUID") as? String ?? ""
        self.IsInvitation = coder.decodeBool(forKey: "IsInvitation")
        self.IsRead = coder.decodeBool(forKey: "IsRead")
        self.MessageText = coder.decodeObject(forKey: "MessageText") as? NSMutableAttributedString ?? NSMutableAttributedString()
        self.OriginalMessage = coder.decodeObject(forKey: "OriginalMessage") as? String ?? ""
        self.Sender = coder.decodeObject(forKey: "Sender") as? Presentity ?? Presentity()
        self.Subject = coder.decodeObject(forKey: "Subject") as? Presentity ?? Presentity()
        self.Time = coder.decodeObject(forKey: "Time") as? NSDate ?? NSDate()

        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(BaseWritingDirection, forKey: "BaseWritingDirection")
        coder.encode(Flags, forKey: "Flags")
        coder.encode(GUID, forKey: "GUID")
        coder.encode(IsInvitation, forKey: "IsInvitation")
        coder.encode(IsRead, forKey: "IsRead")
        coder.encode(MessageText, forKey: "MessageText")
        coder.encode(OriginalMessage, forKey: "OriginalMessage")
        coder.encode(Sender, forKey: "Sender")
        coder.encode(Subject, forKey: "Subject")
        coder.encode(Time, forKey: "Time")
    }
}

class MessageSource_Archive {
    private var msgsBakDirPath: String = ""
    private var idNamedHandles: [String:String] = [:]
    private var fileManager: FileManager
    private var tempDirectoryURL: URL
    var messages: [Message] = []

    func convertBinaryPlistToXML(atPath inputPath: String, outputPath: String) throws {
        let process = Process()
        process.launchPath = "/usr/bin/plutil"
        process.arguments = ["-convert", "xml1", "-o", outputPath, inputPath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.launch()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let errorOutput = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "PlutilErrorDomain", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: errorOutput])
        }
    }

    init(msgsBakDirPath: String, idNamedHandles: [String:String]) {
        self.msgsBakDirPath = msgsBakDirPath
        self.idNamedHandles = idNamedHandles
        self.fileManager = FileManager.default
        self.tempDirectoryURL = self.fileManager.temporaryDirectory
    }

    func readXMLFile(at url: URL) throws {
        let data = try Data(contentsOf: url)
        let parser = XMLParser(data: data)
        let delegate = XMLParserDelegateImpl(messageSource: self)
        parser.delegate = delegate

        if !parser.parse() {
            throw FileError.xmlParsingError
        }
    }

    class XMLParserDelegateImpl: NSObject, XMLParserDelegate {
        var depth = 0
        var elementStack: [String] = []
        var outerKey: String?
        var objectsArrayString: String?
        var objectClassKey: String?
        var objectClassUID: Int?
        var objectKey: String?
        weak var messageSource: MessageSource_Archive?

        init(messageSource: MessageSource_Archive) {
            self.messageSource = messageSource
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String : String] = [:]) {
            elementStack.append(elementName)
            depth += 1
            if debug > 1 {
                print("\(indent(depth))\(depth) <\(elementName)>")
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentElement = elementStack.last

            switch depth {
            case 3:
                if currentElement == "key" {
                    outerKey = trimmedString
                    if debug > 1 {
                        print("key = '\(trimmedString)'")
                    }
                }
            case 4:
                if outerKey == "$objects" && currentElement == "string" {
                    objectsArrayString = trimmedString
                    if debug > 1 {
                        print("objectsArrayString = '\(trimmedString)'")
                    }
                }
            case 5:
                if currentElement == "key" {
                    objectKey = trimmedString
                    if debug > 1 {
                        print("objectKey = '\(trimmedString)'")
                    }
                } else if currentElement == "string" {
                    if objectClassUID == 18 && objectKey == "NS.string" {
                        let message = Message()
                        message.who = "Unknown"
                        message.text = trimmedString
                        messageSource?.messages.append(message)
                        if debug > 0 {
                            print("message = '\(trimmedString)'")
                        }
                     }
                }
           case 6:
                if objectKey == "$class" {
                    if currentElement == "key" {
                        objectClassKey = trimmedString
                        if debug > 1 {
                            print("objectClassKey = '\(trimmedString)'")
                        }
                    } else if currentElement == "integer" {
                        if objectClassKey == "CF$UID" {
                            objectClassUID = Int(trimmedString)
                            if debug > 1 {
                                print("objectClassUID = \(objectClassUID ?? -1)")
                            }
                        }
                    }
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            if debug > 1 {
                print("\(indent(depth))\(depth) </\(elementName)>")
            }
            depth -= 1
            elementStack.removeLast()
        }
    }

    func gatherMessagesFrom(ichatFile fileURL: URL) {
        print("Processing .ichat file: \(fileURL.path)")

        let uniqueFilename = UUID().uuidString
        let tempFileURL = tempDirectoryURL.appendingPathComponent(uniqueFilename
            ).appendingPathExtension("xml")
        do {
            try convertBinaryPlistToXML(atPath: fileURL.path, outputPath: tempFileURL.path)
            //print("Conversion successful, created \(tempFileURL.path)")
        } catch {
            print("Error during conversion to XML: \(error)")
        }
        do {
            try readXMLFile(at: tempFileURL)
            print("Read \(tempFileURL.path).")
        } catch {
            print("Error during XML processing: \(error)")
        }
    }

    // Function to unarchive a .ichat file and print the contents
    func unarchiveIChatFile(fileURL: URL) {
        do {
            // Read the file data
            let fileData = try Data(contentsOf: fileURL)

            // Register necessary classes
            NSKeyedUnarchiver.setClass(Presentity.self, forClassName: "Presentity")
            NSKeyedUnarchiver.setClass(InstantMessage.self, forClassName: "InstantMessage")

            if let unarchivedObject = try NSKeyedUnarchiver.unarchivedObject(ofClasses:
                    [NSDictionary.self, NSArray.self, NSString.self, Presentity.self,
                     InstantMessage.self, NSMutableString.self],
                    from: fileData) as? NSDictionary {
                print("Unarchived Dictionary: \(unarchivedObject)")

                if let topDict = unarchivedObject["$top"] as? NSDictionary {
                    if let metadataRef = topDict["metadata"] as? NSDictionary,
                       let rootRef = topDict["root"] as? NSDictionary,
                       let metadataUID = metadataRef["CF$UID"] as? Int,
                       let rootUID = rootRef["CF$UID"] as? Int {

                        if let objects = unarchivedObject["$objects"] as? NSArray {
                            let metadataObject = objects[metadataUID]
                            let rootObject = objects[rootUID]

                            print("Metadata Object: \(metadataObject)")
                            print("Root Object: \(rootObject)")

                            // Example of resolving a string object
                            if let messageDict = objects[17] as? NSDictionary,
                               let messageString = messageDict["NS.string"] as? String {
                                print("Message: \(messageString)")
                            }
                        }
                    }
                }
            } else {
                print("Failed to cast unarchived object to NSDictionary.")
            }
        } catch {
            print("Error unarchiving file: \(error)")
        }
    }

    func getMessages(inArchive directoryPath: String, forYear year: Int) -> [Message] {
        messages = []
        let directoryURL = URL(fileURLWithPath: directoryPath)

        do {
            // Get the contents of the directory
            let subdirectories = try fileManager.contentsOfDirectory(
                at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles,
                .skipsSubdirectoryDescendants])

            // Filter for subdirectories that start with the specified year
            let yr = "\(year)"
            let yearSubdirectories = subdirectories.filter { $0.hasDirectoryPath &&
                $0.lastPathComponent.hasPrefix(yr) }

            for subdirectory in yearSubdirectories {
                // Get the contents of the subdirectory
                let ichatFiles = try fileManager.contentsOfDirectory(
                    at: subdirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles,
                    .skipsSubdirectoryDescendants])

                // Filter for .ichat files
                let ichatFilesToProcess = ichatFiles.filter { $0.pathExtension == "ichat" }

                for ichatFile in ichatFilesToProcess {
                    // Process the .ichat file
                    //gatherMessagesFrom(ichatFile: ichatFile)
                    unarchiveIChatFile(fileURL: ichatFile)
                }
            }
        } catch {
            print("Error: \(error.localizedDescription)")
        }

        return messages
    }
}
