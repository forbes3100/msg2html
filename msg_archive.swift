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
            throw NSError(domain: "PlutilErrorDomain", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorOutput])
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
        
        if let name = delegate.name {
            print("Name: \(name)")
        } else {
            throw FileError.xmlParsingError
        }
    }
    
    class XMLParserDelegateImpl: NSObject, XMLParserDelegate {
        var currentElement: String?
        var name: String?
        var message: Message = Message()
        weak var messageSource: MessageSource_Archive?
        
        init(messageSource: MessageSource_Archive) {
            self.messageSource = messageSource
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            currentElement = elementName
        }
        
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if currentElement == "name" {
                message.who = string
                messageSource?.messages.append(message)
            }
        }
        
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            currentElement = nil
        }
    }

    func gatherMessagesFrom(ichatFile fileURL: URL) {
        print("Processing .ichat file: \(fileURL.path)")
        
        let uniqueFilename = UUID().uuidString
        let tempFileURL = tempDirectoryURL.appendingPathComponent(uniqueFilename).appendingPathExtension("xml")
        do {
            try convertBinaryPlistToXML(atPath: fileURL.path, outputPath: tempFileURL.path)
            print("Conversion successful, created \(tempFileURL.path)")
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
            let subdirectories = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            
            // Filter for subdirectories that start with the specified year
            let yr = "\(year)"
            let yearSubdirectories = subdirectories.filter { $0.hasDirectoryPath && $0.lastPathComponent.hasPrefix(yr) }
            
            for subdirectory in yearSubdirectories {
                // Get the contents of the subdirectory
                let ichatFiles = try fileManager.contentsOfDirectory(at: subdirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
                
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

    /*
         
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
                    let who = handles[handleId]

                    let msg = Message(
                        who: who,
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
                    messages.append(msg)
                }
            }
        }
         */
}
