// msg_db -- Read from a Mac Messages database
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
import SQLite3

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

class MessageSource_ChatDB {
    private var msgsBakDirPath: String = ""
    private var chatDBFilePath: String = ""
    private var db: OpaquePointer?
    private var idNamedHandles: [String:String] = [:]
    
    init(msgsBakDirPath: String, idNamedHandles: [String:String]) {
        self.msgsBakDirPath = msgsBakDirPath
        self.idNamedHandles = idNamedHandles
        self.chatDBFilePath = getChatDBCopyPath(toDir: msgsBakDirPath)

        guard sqlite3_open_v2(chatDBFilePath, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            fatalError("Opening database \(chatDBFilePath): \(errorMessage)")
        }
        //defer { sqlite3_close(db) }
    }
    
    func getMessagesFor(year: Int) -> [Message] {
        var messages: [Message] = []
        
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

        return messages
    }
}
