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
import CryptoKit

extension String {
    func trimmingLeadingPlus() -> String {
        return String(self.drop(while: { $0 == "+" }))
    }
}

enum FileError: Error {
    case xmlParsingError(String)
}

// Function to convert NSTimeInterval to Date
func convertNSTimeIntervalToDate(_ timeInterval: TimeInterval) -> Date {
    // The reference date is January 1, 2001
    let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
    return referenceDate.addingTimeInterval(timeInterval)
}

// Function to format Date to String
func formatDate(_ date: Date) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .medium
    dateFormatter.timeZone = TimeZone.current // Use the current timezone
    return dateFormatter.string(from: date)
}

func findGUIDSubdirectory(in attachmentsDirectory: URL, guid: String) -> URL? {
    let fileManager = FileManager.default
    
    // Function to recursively search for the GUID directory
    func searchDirectory(at url: URL) -> URL? {
        do {
            let contents = try fileManager.contentsOfDirectory(at: url,
                                includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for item in contents {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory)
                        && isDirectory.boolValue {
                    if item.lastPathComponent == guid {
                        return item
                    } else if let found = searchDirectory(at: item) {
                        return found
                    }
                }
            }
        } catch {
            print("Error reading directory: \(error)")
        }
        return nil
    }
    
    return searchDirectory(at: attachmentsDirectory)
}


class MessageSource_Archive {
    private var fileManager: FileManager
    var attachmentsURL: URL!
    var participantNamesByID: [String: String] = [:]
    var myID: String? = nil
    var messages: [Message] = []

    init() {
        self.fileManager = FileManager.default
    }

    // Helper function to extract value from CFKeyedArchiverUID description
    func extractValue(from uidDescription: String) -> Int? {
        let pattern = "\\{value = (\\d+)\\}"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: uidDescription, options: [], range:
                                            NSRange(location: 0, length: uidDescription.count)) {
            if let range = Range(match.range(at: 1), in: uidDescription) {
                return Int(uidDescription[range])
            }
        }
        return nil
    }

    // Helper function to resolve CFKeyedArchiverUID references
    func resolveUID(_ uid: Any, from objects: [Any]) -> Any? {
        if let uidValue = extractValue(from: "\(uid)"), uidValue < objects.count {
            return objects[uidValue]
        }
        return nil
    }

    class Presentity {
        var id: String
        var name: String
        var isMe: Bool
        weak var parent: MessageSource_Archive?

        init (uid: Int, from objects: [Any], parent: MessageSource_Archive) {
            guard let presentity = objects[uid] as? [String: Any] else {
                fatalError("Failed to cast Presentity at UID \(uid).")
            }

            guard let idRef = presentity["ID"],
                  let idFull = parent.resolveUID(idRef, from: objects) as? String else {
                fatalError("Failed to cast Presentity.ID.")
            }
            self.id = idFull.trimmingLeadingPlus()
            self.name = parent.participantNamesByID[id] ?? ""
            self.isMe = id.starts(with: parent.myID ?? "-")
        }
    }

    class ArchiveNSDictionary {
        var keys: [String]
        var objects: [Any]
        weak var parent: MessageSource_Archive?

        init(_ xml: Any, from objects: [Any], parent: MessageSource_Archive) {
            guard let xmlDict = xml as? [String: Any],
                  let nsKeys = xmlDict["NS.keys"] as? [Any] else {
                fatalError("Failed to find NS.keys in an Archive NSDictionary")
            }
            self.keys = []
            for keyRef in nsKeys {
                guard let keyName = parent.resolveUID(keyRef, from: objects) as? String else {
                    fatalError("Failed to get key in an Archive NSDictionary")
                }
                self.keys.append(keyName)
            }
            guard let nsObjects = xmlDict["NS.objects"] as? [Any] else {
                fatalError("Failed to find NS.objects in an Archive NSDictionary")
            }
            self.objects = []
            for objectRef in nsObjects {
                guard let object = parent.resolveUID(objectRef, from: objects) else {
                    fatalError("Failed to get object in an Archive NSDictionary")
                }
                self.objects.append(object)
            }
            self.parent = parent
        }

        // Subscript to access values by key (getter only)
        subscript(key: String) -> Any? {
            get {
                if let index = keys.firstIndex(of: key) {
                    return objects[index]
                }
                return nil
            }
        }

        // Function to get all keys
        func allKeys() -> [String] {
            return keys
        }

        // Function to get all values
        func allValues() -> [Any] {
            return objects
        }

        // Function to get the count of key-value pairs
        func count() -> Int {
            return keys.count
        }
    }

    // Parse message style/attachment and return attached file's name and URL, if any.
    func parse(styleAttachment: [String: Any], from objects: [Any],
                       parent: MessageSource_Archive) -> (String?, URL?) {
        let attachmentDict = ArchiveNSDictionary(styleAttachment, from: objects, parent: self)
        //print("\(attachmentDict)")
        if let fileGUID = attachmentDict["__kIMFileTransferGUIDAttributeName"] as? String,
           let fileName = attachmentDict["__kIMFilenameAttributeName"] as? String {
            // have attached file's path: return URL if file exists
            if let guidDirectory = findGUIDSubdirectory(in: parent.attachmentsURL, guid: fileGUID) {
                let attachmentURL = guidDirectory.appendingPathComponent(fileName)
                if debug > 1 {
                    let d = guidDirectory.pathComponents.suffix(4).joined(separator: "/")
                    print("Attachment: \(d)/\(fileName)")
                }
                return (fileName, attachmentURL)
            } else {
                // return attachment file name, but no URL
                return (fileName, nil)
            }
        }
        // no attachment, just simple text style
        return (nil, nil)
    }

    // Unarchive a .ichat file and add to messages array
    func gatherMessagesFrom(ichatFile fileURL: URL, attachmentsURL: URL) throws {
        // Read the file data
        let fileData = try Data(contentsOf: fileURL)
        print("\n\ngatherMessagesFrom(ichatFile=\(fileURL.lastPathComponent)")
        self.attachmentsURL = attachmentsURL
        print("attachmentURL=\(attachmentsURL.lastPathComponent))")

        // Deserialize the plist
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try PropertyListSerialization.propertyList(from: fileData,
                    options: .mutableContainersAndLeaves, format: &format) as? [String: Any] else {
            fatalError("Failed to parse plist.")
        }
        //print("Parsed Plist: \(plist)")

        // Access the $top dictionary
        guard let topDict = plist["$top"] as? [String: Any] else {
            fatalError("Failed to cast '$top' to dictionary.")
        }
        //print("Top Dictionary: \(topDict)")

        // Extract the CF$UID references for metadata and root
        guard let metadataRef = topDict["metadata"],
              let rootRef = topDict["root"],
              let objects = plist["$objects"] as? [Any] else {
            fatalError("Failed to extract 'metadata' or 'root' refs or cast '$objects' to array.")
        }

        // Resolve the metadata object using its UID reference
        guard let metadataDict = resolveUID(metadataRef, from: objects) as? [String: Any],
              let metadataArray = metadataDict["NS.objects"] as? NSArray else {
            fatalError("Failed to retrieve metadata object.")
        }
        if debug > 1 {
            print("Metadata Object: \(metadataArray)")
        }

        // Get participant names from metadata
        let participantsRef = metadataArray[4]
        guard let participantsDict = resolveUID(participantsRef, from: objects) as? [String: Any],
              let participantsArray = participantsDict["NS.objects"] as? NSArray else {
            fatalError("Failed to cast metadata.Participants.")
        }

        // Get presentity IDs from metadata
        let presentityIDsRef = metadataArray[6]
        guard let presentityIDsDict = resolveUID(presentityIDsRef, from: objects) as? [String: Any],
              let presentityIDsArray = presentityIDsDict["NS.objects"] as? NSArray else {
            fatalError("Failed to cast metadata.PresentityIDs.")
        }

        // Assign names to IDs
        for (participantRef, presentityIDRef) in zip(participantsArray, presentityIDsArray) {
            guard let participantNameObject = resolveUID(participantRef, from: objects) else {
                fatalError("Failed to cast Participant name object.")
            }
            var participantName = ""
            if let participant = participantNameObject as? String {
                participantName = participant
            } else if let participantDict = participantNameObject as? [String: Any],
                      let participant = participantDict["NS.string"] as? String {
                participantName = participant
            } else {
                fatalError("Failed to cast Participant name.")
            }
            guard let presentityIDObject = resolveUID(presentityIDRef, from: objects) else {
                fatalError("Failed to cast PresentityID object.")
            }
            var presentityID = ""
            if let presentityIDMString = presentityIDObject as? [String: Any],
               let id = presentityIDMString["NS.string"] as? String {
                presentityID = id
            } else if let id = presentityIDObject as? String {
                presentityID = id
            } else {
                fatalError("Failed to cast PresentityID.")
            }
            participantNamesByID[presentityID] = participantName
            // First presentity is owner's
            if myID == nil {
                myID = presentityID
            }
        }

        // Resolve the root object using its UID reference
        guard let rootRaw = resolveUID(rootRef, from: objects) else {
            fatalError("Failed to retrieve root object.")
        }
        //print("Root Raw Object: \(rootRaw)")

        // Check if the rootRaw object is a dictionary and extract the array from NS.objects
        guard let rootDict = rootRaw as? [String: Any],
              let root = rootDict["NS.objects"] as? NSArray else {
            fatalError("Failed to cast root object to dictionary or extract NS.objects.")
        }
        if debug > 1 {
            print("Root: \(root)")
        }

        // Extract the service name
        guard let service = resolveUID(root[0], from: objects) as? String else {
            fatalError("Failed to get service name.")
        }

        // Extract the InstantMessage references array
        guard let imsDict = resolveUID(root[2], from: objects) as? [String: Any],
              let ims = imsDict["NS.objects"] as? NSArray else {
            fatalError("Failed to cast InstantMessage array.")
        }

        // Iterate over InstantMessages
        var isFirst = true
        var presentities: [Int: Presentity] = [:]
        for (index, imRef) in ims.enumerated() {
            guard let im = resolveUID(imRef, from: objects) as? [String:Any] else {
                fatalError("Failed to cast InstantMessage \(index).")
            }

            // Handle InstantMessage elements
            //print("InstantMessage[\(index)] = \(im)")
            // Insure that the message sender's Presentity record is in presentities dict
            let message = Message()
            guard let senderRef = im["Sender"],
                  let senderUID = extractValue(from: "\(senderRef)") else {
                fatalError("Failed to cast InstantMessage.Sender.")
            }
            print("Message[\(index)].Sender UID = \(senderUID)")
            if !presentities.keys.contains(senderUID) {
                presentities[senderUID] = Presentity(uid: senderUID, from: objects, parent: self)
            }
            message.fileName = fileURL.path
            let sender = presentities[senderUID]!
            message.who = sender.name
            message.svc = service
            message.threadID = sender.id
            message.isFirst = isFirst
            isFirst = false
            message.isFromMe = sender.isMe
            message.rowid = index
            print("Message[\(index)].fileName = \(message.fileName), .rowid = \(message.rowid)")
            print("Message[\(index)].who = \(message.who ?? "?"), .isFromMe=\(message.isFromMe)")

            // Get message date and time
            guard let dateRef = im["Time"],
                  let dateDict = resolveUID(dateRef, from: objects) as? [String: Any],
                  let timeInterval = dateDict["NS.time"] as? TimeInterval else {
                fatalError("Failed to cast InstantMessage.Date.")
            }
            let date = convertNSTimeIntervalToDate(timeInterval)
            print("Message[\(index)].Date = \(formatDate(date))")
            message.date = date

            // Get message Globally Unique Identifier
            guard let guidRef = im["GUID"],
                  let guid = resolveUID(guidRef, from: objects) as? String else {
                fatalError("Failed to cast InstantMessage.GUID.")
            }
            print("Message[\(index)].GUID = \(guid)")
            message.guid = guid

            // Get message attributes (including attachments) and text
            var text = ""
            var attachments: [(String, URL?)] = []
            if let textRef = im["MessageText"] {
                // parse text's NSMutableAttributedString
                guard let textDict = resolveUID(textRef, from: objects) as? [String: Any],
                      // parse attributes first
                      let nsAttributesRef = textDict["NSAttributes"],
                      let nsAttributes = resolveUID(nsAttributesRef,
                                                        from: objects) as? [String: Any] else {
                    fatalError("Failed to cast InstantMessage.MessageText.")
                }

                guard let nsAttributesClassRef = nsAttributes["$class"],
                      let nsAttributesClass = resolveUID(nsAttributesClassRef,
                                                         from: objects) as? [String: Any?],
                      let nsAttributesClassName = nsAttributesClass["$classname"] as? String else {
                    fatalError("Failed to get InstantMessage.MessageText.NSAttributes.$class")
                }

                // if MessageText.NSAttributes is an array, it contains attachments
                if nsAttributesClassName == "NSMutableArray" {
                    guard let nsAttributesArray = nsAttributes["NS.objects"] as? [Any] else {
                        fatalError("Failed to get InstantMessage.MessageText.NSAttributes objects")
                    }
                    for (index, attachmentRef) in nsAttributesArray.enumerated() {
                        print("Attachment \(index): \(attachmentRef)")
                        guard let styleAttachment = resolveUID(attachmentRef,
                                                          from: objects) as? [String:Any] else {
                            fatalError("Failed to get attachment \(index)")
                        }
                        // ignore style-only element, but get styled attachment
                        let (fileName, attachment) = parse(styleAttachment: styleAttachment,
                                                           from: objects, parent: self)
                        if let fileName = fileName {
                            attachments.append((fileName, attachment))
                        }
                    }
                } else if nsAttributesClassName == "NSDictionary" {
                    // if MessageText.NSAttributes is a dictionary, it's a single style+attachment
                    let (fileName, attachment) = parse(styleAttachment: nsAttributes,
                                                          from: objects, parent: self)
                    if let fileName = fileName {
                        attachments.append((fileName, attachment))
                    }
                }

                guard let nsStringRef = textDict["NSString"],
                      let nsStringDict = resolveUID(nsStringRef, from: objects) as? [String: Any],
                      let msgText = nsStringDict["NS.string"] as? String else {
                    fatalError("Failed to cast InstantMessage.MessageText.")
                }
                text = msgText
            } else {
                guard let textRef = im["OriginalMessage"],
                      let orignalText = resolveUID(textRef, from: objects) as? String else {
                    fatalError("Failed to cast InstantMessage.OriginalMessage.")
                }
                text = orignalText
            }
            print("Message[\(index)] = '\(text)'")
            message.text = text
            message.attachments = attachments
            messages.append(message)
        }
    }

    func getMessages(inArchive directoryPath: String, attachmentsURL: URL,
                     forYear year: Int) -> [Message] {
        messages = []
        let directoryURL = URL(fileURLWithPath: directoryPath)

        do {
            // Get the contents of the directory
            let subdirectories = try fileManager.contentsOfDirectory(
                at: directoryURL, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])

            // Filter for subdirectories that start with the specified year
            let yr = "\(year)"
            var yearSubdirs = subdirectories.filter { $0.hasDirectoryPath &&
                $0.lastPathComponent.hasPrefix(yr) }
            yearSubdirs = yearSubdirs.sorted { $0.lastPathComponent < $1.lastPathComponent }

            for subdirectory in yearSubdirs {
                // Get the contents of the subdirectory
                var ichatFiles = try fileManager.contentsOfDirectory(
                    at: subdirectory, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])

                // Filter for and sort .ichat files
                ichatFiles = ichatFiles.filter { $0.pathExtension == "ichat" }
                ichatFiles = ichatFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }

                for ichatFile in ichatFiles {
                    try gatherMessagesFrom(ichatFile: ichatFile, attachmentsURL: attachmentsURL)
                }
            }
        } catch let FileError.xmlParsingError(message) {
            print("Error: \(message)")
        } catch {
            print("Error: \(error.localizedDescription)")
        }

        return messages
    }
}
