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

class MessageSource_Archive {
    private var fileManager: FileManager
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

        init (uid: Int, from objects: [Any], parent: MessageSource_Archive) throws {
            guard let presentity = objects[uid] as? [String: Any] else {
                throw FileError.xmlParsingError("Failed to cast Presentity at UID \(uid).")
            }

            guard let idRef = presentity["ID"],
                  let idFull = parent.resolveUID(idRef, from: objects) as? String else {
                throw FileError.xmlParsingError("Failed to cast Presentity.ID.")
            }
            self.id = idFull.trimmingLeadingPlus()
            self.name = parent.participantNamesByID[id] ?? ""
            self.isMe = (id == parent.myID)
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
        var presentities: [Int: Presentity] = [:]
        for (index, imRef) in imsArray.enumerated() {
            guard let im = resolveUID(imRef, from: objects) as? [String:Any] else {
                throw FileError.xmlParsingError("Failed to cast InstantMessage \(index).")
            }

            // Handle InstantMessage elements
            //print("InstantMessage[\(index)] = \(im)")

            let message = Message()
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
            message.rowid = index

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

            var text = ""
            if let textRef = im["OriginalMessage"] {
                guard let orignalText = resolveUID(textRef, from: objects) as? String else {
                    throw FileError.xmlParsingError("Failed to cast InstantMessage.OriginalMessage.")
                }
                text = orignalText
            } else {
                guard let textRef = im["MessageText"],
                      let textDict = resolveUID(textRef, from: objects) as? [String: Any],
                      let nsStringRef = textDict["NSString"],
                      let nsStringDict = resolveUID(nsStringRef, from: objects) as? [String: Any],
                      let msgText = nsStringDict["NS.string"] as? String else {
                    throw FileError.xmlParsingError("Failed to cast InstantMessage.MessageText.")
                }
                text = msgText
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
