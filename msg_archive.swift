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
    case xmlParsingError(String)
}

import Foundation

/*
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
    //var IsRead: Bool
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
        //self.IsRead = coder.decodeBool(forKey: "IsRead")
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
        //coder.encode(IsRead, forKey: "IsRead")
        coder.encode(MessageText, forKey: "MessageText")
        coder.encode(OriginalMessage, forKey: "OriginalMessage")
        coder.encode(Sender, forKey: "Sender")
        coder.encode(Subject, forKey: "Subject")
        coder.encode(Time, forKey: "Time")
    }
}

class NSParagraphStyle: NSObject, NSSecureCoding {
    var NSName: String
    var NSSize: Int
    var NSfFlags: Int

    static var supportsSecureCoding: Bool {
        return true
    }

    required init?(coder: NSCoder) {
        // Initialize all properties with default values before calling super.init()
        self.NSName = coder.decodeObject(forKey: "NSName") as? String ?? ""
        self.NSSize = coder.decodeInteger(forKey: "NSSize")
        self.NSfFlags = coder.decodeInteger(forKey: "NSfFlags")

        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(NSName, forKey: "NSName")
        coder.encode(NSSize, forKey: "NSSize")
        coder.encode(NSfFlags, forKey: "NSfFlags")
    }

    override init() {
        // Initialize properties with default values
        self.NSName = ""
        self.NSSize = 0
        self.NSfFlags = 0

        super.init()
    }
}

class NSMutableParagraphStyle: NSObject, NSSecureCoding {
    var NSAlignment: Int
    var NSAllowsTighteningForTruncation: Int
    var NSTabStops: String

    static var supportsSecureCoding: Bool {
        return true
    }

    required init?(coder: NSCoder) {
        // Initialize all properties with default values before calling super.init()
        self.NSAlignment = coder.decodeInteger(forKey: "NSAlignment")
        self.NSAllowsTighteningForTruncation = coder.decodeInteger(forKey:
                                    "NSAllowsTighteningForTruncation")
        self.NSTabStops = coder.decodeObject(forKey: "NSTabStops") as? String ?? ""

        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(NSAlignment, forKey: "NSAlignment")
        coder.encode(NSAllowsTighteningForTruncation, forKey: "NSAllowsTighteningForTruncation")
        coder.encode(NSTabStops, forKey: "NSTabStops")
    }

    override init() {
        // Initialize properties with default values
        self.NSAlignment = 0
        self.NSAllowsTighteningForTruncation = 0
        self.NSTabStops = ""

        super.init()
    }
}

// Define a custom class to represent CFKeyedArchiverUID objects
class CFKeyedArchiverUID: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool {
        return true
    }

    var value: Int

    init(value: Int) {
        self.value = value
    }

    required init?(coder: NSCoder) {
        self.value = coder.decodeInteger(forKey: "value")
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(value, forKey: "value")
    }
}
*/

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

class MessageSource_Archive {
    private var fileManager: FileManager
    var participantNamesByID: [String: String] = [:]
    var myID: String? = nil
    var messages: [Message] = []

    init(msgsBakDirPath: String, idNamedHandles: [String:String]) {
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
        var anonymousKey: String
        var name: String
        var isMe: Bool
        weak var parent: MessageSource_Archive?

        init (uid: Int, from objects: [Any], parent: MessageSource_Archive) throws {
            guard let presentity = objects[uid] as? [String: Any] else {
                throw FileError.xmlParsingError("Failed to cast Presentity at UID \(uid).")
            }
            guard let anonymousKeyRef = presentity["AnonymousKey"] else {
                throw FileError.xmlParsingError("Failed to parse AnonymousKey reference.")
            }
            var anonymousKey = ""
            if let _ = anonymousKeyRef as? Bool {
            } else {
                guard let key = parent.resolveUID(anonymousKeyRef, from: objects) as? String else {
                    throw FileError.xmlParsingError("Failed to cast AnonymousKey.")
                }
                anonymousKey = key
            }
            print("AnonymousKey = '\(anonymousKey)'")
            self.anonymousKey = anonymousKey
            self.name = parent.participantNamesByID[anonymousKey] ?? ""
            self.isMe = (anonymousKey == parent.myID)
        }
    }

    // Unarchive a .ichat file and add to messages array
    func gatherMessagesFrom(ichatFile fileURL: URL) throws {
        // Read the file data
        let fileData = try Data(contentsOf: fileURL)

        // Deserialize the plist
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try PropertyListSerialization.propertyList(from: fileData, options: .mutableContainersAndLeaves, format: &format) as? [String: Any] else {
            throw FileError.xmlParsingError("Failed to parse plist.")
        }
        //print("Parsed Plist: \(plist)")

        // Access the $top dictionary
        guard let topDict = plist["$top"] as? [String: Any] else {
            throw FileError.xmlParsingError("Failed to cast '$top' to dictionary.")
        }
        //print("Top Dictionary: \(topDict)")

        // Extract the CF$UID references for metadata and root
        guard let metadataRef = topDict["metadata"], let rootRef = topDict["root"],
              let objects = plist["$objects"] as? [Any] else {
            throw FileError.xmlParsingError("Failed to extract 'metadata' or 'root' refs or cast '$objects' to array.")
        }

        // Resolve the metadata object using its UID reference
        guard let metadataDict = resolveUID(metadataRef, from: objects) as? [String: Any],
              let metadataArray = metadataDict["NS.objects"] as? NSArray else {
            throw FileError.xmlParsingError("Failed to retrieve metadata object.")
        }
        //print("Metadata Object: \(metadataObject)")

        // Get participant names from metadata
        let participantsRef = metadataArray[4]
        guard let participantsDict = resolveUID(participantsRef, from: objects) as? [String: Any],
              let participantsArray = participantsDict["NS.objects"] as? NSArray else {
            throw FileError.xmlParsingError("Failed to cast metadata.Participants.")
        }

        // Get presentity IDs from metadata
        let presentityIDsRef = metadataArray[6]
        guard let presentityIDsDict = resolveUID(presentityIDsRef, from: objects) as? [String: Any],
              let presentityIDsArray = presentityIDsDict["NS.objects"] as? NSArray else {
            throw FileError.xmlParsingError("Failed to cast metadata.PresentityIDs.")
        }

        // Assign names to IDs
        for (participantRef, presentityIDRef) in zip(participantsArray, presentityIDsArray) {
            guard let participant = resolveUID(participantRef, from: objects) as? String else {
                throw FileError.xmlParsingError("Failed to cast Participant.")
            }
            guard let presentityIDObject = resolveUID(presentityIDRef, from: objects) else {
                throw FileError.xmlParsingError("Failed to cast PresentityID object.")
            }
            var presentityID = ""
            if let presentityIDMString = presentityIDObject as? [String: Any],
               let id = presentityIDMString["NS.string"] as? String {
                presentityID = id
            } else if let id = presentityIDObject as? String {
                presentityID = id
            } else {
                throw FileError.xmlParsingError("Failed to cast PresentityID.")
            }
            participantNamesByID[presentityID] = participant
            // First presentity is owner's
            if myID == nil {
                myID = presentityID
            }
        }

        // Resolve the root object using its UID reference
        guard let rootRaw = resolveUID(rootRef, from: objects) else {
            throw FileError.xmlParsingError("Failed to retrieve root object.")
        }
        //print("Root Raw Object: \(rootRaw)")

        // Check if the rootRaw object is a dictionary and extract the array from NS.objects
        guard let rootDict = rootRaw as? [String: Any],
              let rootArray = rootDict["NS.objects"] as? NSArray else {
            throw FileError.xmlParsingError("Failed to cast root object to dictionary or extract NS.objects.")
        }
        //print("Root Array: \(rootArray)")

        // Extract the InstantMessage references array
        guard let imsArrayDict = resolveUID(rootArray[2], from: objects) as? [String: Any],
              let imsArray = imsArrayDict["NS.objects"] as? NSArray else {
            throw FileError.xmlParsingError("Failed to cast InstantMessage array.")
        }

        // Iterate over InstantMessages
        for (index, imRef) in imsArray.enumerated() {
            guard let im = resolveUID(imRef, from: objects) as? [String:Any] else {
                throw FileError.xmlParsingError("Failed to cast InstantMessage \(index).")
            }

            // Handle InstantMessage elements
            //print("InstantMessage[\(index)] = \(im)")

            let message = Message()
            var presentities: [Int: Presentity] = [:]
            guard let senderRef = im["Sender"],
                  let senderUID = extractValue(from: "\(senderRef)") else {
                throw FileError.xmlParsingError("Failed to cast InstantMessage.Sender.")
            }
            print("Message[\(index)].Sender UID = \(senderUID)")
            if !presentities.keys.contains(senderUID) {
                try presentities[senderUID] = Presentity(uid: senderUID, from: objects, parent: self)
            }
            let sender = presentities[senderUID]!
            message.who = sender.name
            message.isFromMe = sender.isMe

            guard let dateRef = im["Time"],
                  let dateDict = resolveUID(dateRef, from: objects) as? [String: Any],
                  let timeInterval = dateDict["NS.time"] as? TimeInterval else {
                throw FileError.xmlParsingError("Failed to cast InstantMessage.Date.")
            }
            let date = convertNSTimeIntervalToDate(timeInterval)
            print("Message[\(index)].Date = \(formatDate(date))")
            message.date = date

            guard let guidRef = im["GUID"],
                  let guid = resolveUID(guidRef, from: objects) as? String else {
                throw FileError.xmlParsingError("Failed to cast InstantMessage.GUID.")
            }
            print("Message[\(index)].GUID = \(guid)")
            message.guid = guid

            guard let textRef = im["OriginalMessage"],
                  let text = resolveUID(textRef, from: objects) as? String else {
                throw FileError.xmlParsingError("Failed to cast InstantMessage.OriginalMessage.")
            }
            print("Message[\(index)] = '\(text)'")
            message.text = text
            messages.append(message)
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
                    try gatherMessagesFrom(ichatFile: ichatFile)
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
