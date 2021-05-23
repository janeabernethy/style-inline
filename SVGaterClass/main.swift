#!/usr/bin/swift

import Foundation

enum SVGConversionError: Error {
    case idsNotFound
    case newFileName
    case createFile(filePath: String)
    case convertingStringToData
    case writingToFile(systemError: NSError)
}

extension SVGConversionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .idsNotFound:
            return NSLocalizedString("Could not convert IDs to Classes - no IDs found", comment: "idsNotFound")
        case .newFileName:
            return NSLocalizedString("Error creating new file with name", comment: "newFileName")
        case .createFile(let filePath):
            return NSLocalizedString("Could not create new SVG file at path: \(filePath)", comment: "couldNotCreateFile")
        case .convertingStringToData:
            return NSLocalizedString("Could not convert SVG string to data type", comment: "couldNotConvertStringToData")
        case .writingToFile(let systemError):
            return "Error writing new SVG to file: \(systemError.localizedDescription)"
        }
    }
}

func changeIdsToClasses(svgString: String) -> Result<String, Error> {
    var updatedSVGString = svgString

    let idRegex = try! NSRegularExpression(pattern: "#[\\w\\d]+\\S")
    let svgNSRange = NSRange(location: 0, length: updatedSVGString.utf16.count)
    let idRanges = idRegex.matches(in: updatedSVGString, options: [], range: svgNSRange)
    
    
    //2. find IDs used
    guard idRanges.count > 0 else {
        return .failure(SVGConversionError.idsNotFound)
    }
    
    print("**** Found IDS: \(idRanges.count)");
    
    var ids = [String]()
    
    idRanges.forEach { result in
        let startIndex = updatedSVGString.index(updatedSVGString.startIndex, offsetBy: result.range.location + 1)
        let endIndex = updatedSVGString.index(startIndex, offsetBy: result.range.length - 1)
        let id = updatedSVGString[startIndex..<endIndex]
        ids.append(String(id))
        
        let hashStart = updatedSVGString.index(updatedSVGString.startIndex, offsetBy: result.range.location)
        let hashEnd = updatedSVGString.index(hashStart, offsetBy: 1)
        let hashRange: Range = hashStart..<hashEnd
        updatedSVGString.replaceSubrange(hashRange, with: ".")
    }
    
    //4. replace ids with classes in HTML

    let svgStartIndex = updatedSVGString.index(updatedSVGString.startIndex, offsetBy: 0)
    let svgEndIndex = updatedSVGString.index(svgStartIndex, offsetBy: updatedSVGString.count)
    let svgRange: Range = svgStartIndex..<svgEndIndex
    for id in ids {
        let idSubstring = "id=\"\(id)\""
        let classSubstring = "class=\"\(id)\""
        updatedSVGString = updatedSVGString.replacingOccurrences(of: idSubstring, with: classSubstring, options: [], range: svgRange)
    }
    return .success(updatedSVGString)
}

func writeNewSVGFile(svgString: String, existingFilePath: String) -> Result<String, Error> {
    let pathComponents = existingFilePath.components(separatedBy: "/")
    guard let newFilename = pathComponents.last?.replacingOccurrences(of: ".svg", with: "-updated.svg") else {
        return .failure(SVGConversionError.newFileName)
    }

    var newPathComponents = pathComponents.dropLast()
    newPathComponents.append(String(newFilename))
    let newPath = newPathComponents.joined(separator: "/")
    
    guard let outputURL = URL(string: "file://" + newPath) else {
        return .failure(SVGConversionError.createFile(filePath: newPath))
    }
    
    guard let data = svgString.data(using: String.Encoding.utf8) else {
        return .failure(SVGConversionError.convertingStringToData)
    }
        
    do {
        try data.write(to: outputURL)
        return .success(newPath)
    }
    catch let error as NSError {
        return .failure(SVGConversionError.writingToFile(systemError: error))
    }
}

// Starts here 👇
guard CommandLine.arguments.count > 1 else {
    print("Usage: 'main.swift file.svg' - provdide svg file")
    exit(1)
}

let path = CommandLine.arguments[1]
do {
    //1. get conents of file
    let contents = try String(contentsOfFile: path, encoding: .utf8)
    
    //2. update contents of file
    let updatedSVGResult = changeIdsToClasses(svgString: contents)
    switch updatedSVGResult {
    case .success(let updatedString):
        //3. write to new SVG file
        let newFileResult = writeNewSVGFile(svgString: updatedString, existingFilePath: path)
        switch newFileResult {
        case .success(let path):
            print("🎉 SVG updated at: \(path)")
        case .failure(let error):
            print(error.localizedDescription)
            exit(3)
        }
    case .failure(let error):
        print(error.localizedDescription)
        exit(2)
    }
}
catch let error as NSError {
    print("Error reading file: \(error.localizedDescription)")
}
