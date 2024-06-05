//
//  msg2html_main.swift
//  macbak
//
//  Created by Scott Forbes on 5/23/24.
//

import Foundation

struct Config: Codable {
    var startYear: Int?
    var endYear: Int?
    var debugLevel: Int?
    var msgsDir: String?
    var externalAttachmentLibrary: String?
    
    init(startYear: Int? = nil, endYear: Int? = nil, debugLevel: Int? = nil,
         msgsDir: String? = nil, externalAttachmentLibrary: String? = nil) {
        self.startYear = startYear
        self.endYear = endYear
        self.debugLevel = debugLevel
        self.msgsDir = msgsDir
        self.externalAttachmentLibrary = externalAttachmentLibrary
    }
}

func getConfigFileURL() -> URL? {
    let fileManager = FileManager.default
    
    if let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        let configDirectory = appSupportDirectory.appendingPathComponent("msg2html")
        
        do {
            try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create directory: \(error)")
            return nil
        }
        
        return configDirectory.appendingPathComponent("config.plist")
    }
    
    return nil
}

func readConfigFile() -> Config? {
    if let configFileURL = getConfigFileURL() {
        do {
            let data = try Data(contentsOf: configFileURL)
            let decoder = PropertyListDecoder()
            let config = try decoder.decode(Config.self, from: data)
            return config
        } catch {
            print("Failed to read config file-- using defaults.")
        }
    }
    return nil
}

func writeConfigFile(_ config: Config) {
    if let configFileURL = getConfigFileURL() {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        
        do {
            let data = try encoder.encode(config)
            try data.write(to: configFileURL)
        } catch {
            print("Failed to write config file: \(error)")
        }
    }
}

func showUsage() {
    print("Usage: msg2html [<start_year>] [end_year] [-d debug_level] [-m msgs_dir] [-e external_attachment_library]")
}

func parseCommandLineArguments() -> Config {
    let arguments = CommandLine.arguments
    let argumentCount = arguments.count
    
    var config = Config()
    var index = 1

    if argumentCount >= 2, let startYear = Int(arguments[1]) {
        config.startYear = startYear
        index += 1
    }
    if argumentCount >= 3, let endYear = Int(arguments[2]) {
        config.endYear = endYear
        index += 1
    }
    
    while index < argumentCount {
        switch arguments[index] {
        case "-d":
            if index + 1 < argumentCount, let debugLevel = Int(arguments[index + 1]) {
                config.debugLevel = debugLevel
                index += 1
            } else {
                print("Invalid value for -d")
                exit(1)
            }
        case "-m":
            if index + 1 < argumentCount {
                config.msgsDir = arguments[index + 1]
                index += 1
            } else {
                print("Invalid value for -m")
                exit(1)
            }
        case "-e":
            if index + 1 < argumentCount {
                config.externalAttachmentLibrary = arguments[index + 1]
                index += 1
            } else {
                print("Invalid value for -e")
                exit(1)
            }
        case "-h":
            showUsage()
            exit(1)
        default:
            break
        }
        index += 1
    }
    
    return config
}

func msg2html() {

    var config = readConfigFile() ?? Config()

    let cliConfig = parseCommandLineArguments()

    config.startYear = cliConfig.startYear
    config.endYear = cliConfig.endYear ?? config.endYear
    config.debugLevel = cliConfig.debugLevel
    config.msgsDir = cliConfig.msgsDir
    config.externalAttachmentLibrary = cliConfig.externalAttachmentLibrary ?? config.externalAttachmentLibrary

    writeConfigFile(config)

    print("Configuration: \(config)")
    if config.startYear == nil || config.msgsDir == nil {
        if config.startYear == nil {
            print("Missing start_year")
        }
        if config.msgsDir == nil {
            print("Missing msgs_dir")
        }
        showUsage()
        exit(1)
    }
    if let dl = config.debugLevel {
        debug = dl
    }

    let archiveDir = config.msgsDir! + "/Archive"
    convertMessages(from: archiveDir, msgsDir: config.msgsDir!, attachments: "Attachments",
                    extAttachments: config.externalAttachmentLibrary,
                    year: config.startYear!, toYear: config.endYear, toHtmlFile: "")
}

msg2html()
