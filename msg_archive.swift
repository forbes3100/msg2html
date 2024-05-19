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
                    gatherMessagesFrom(ichatFile: ichatFile)
                }
            }
        } catch {
            print("Error: \(error.localizedDescription)")
        }

        return messages
    }
}
