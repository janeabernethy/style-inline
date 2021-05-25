#!/usr/bin/swift

import Foundation

struct StyleInfo {
    var id: String
    var style: String
    var idWithStyleRange: NSRange
}

enum SVGConversionError: Error {
    case idsNotFound
    case newFileName
    case createFile(filePath: String)
    case convertingStringToData
    case writingToFile(systemError: NSError)
    case couldNotFindMatch(matchLocation: String)
    case couldNotConvertRangeToNSRange
}

extension SVGConversionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .idsNotFound:
            return NSLocalizedString("Could not convert IDs to Classes - no IDs found", comment: "")
        case .newFileName:
            return NSLocalizedString("Error creating new file with name", comment: "")
        case .createFile(let filePath):
            return NSLocalizedString("Could not create new SVG file at path: \(filePath)", comment: "")
        case .convertingStringToData:
            return NSLocalizedString("Could not convert SVG string to data type", comment: "")
        case .writingToFile(let systemError):
            return NSLocalizedString("Error writing new SVG to file: \(systemError.localizedDescription)", comment: "")
        case .couldNotFindMatch(let location):
            return NSLocalizedString("Could not find regex match for: \(location)", comment: "")
        case .couldNotConvertRangeToNSRange:
            return NSLocalizedString("Could not convert NSRange to Range", comment: "")
        }
    }
}

func changeIdsToInline(svgString: String) -> Result<String, Error> {
    var updatedSVGString = svgString

    let idRegex = try! NSRegularExpression(pattern: "#[\\w\\d]+\\S")
    let idWithStyleRegex = try! NSRegularExpression(pattern: "#[\\w\\d\\s]+\\{[\\w\\d\\s:]+\\}")
    let styleRegex = try! NSRegularExpression(pattern: "\\{[\\w\\d\\s:]+\\}")
    let svgNSRange = NSRange(location: 0, length: updatedSVGString.utf16.count)
    let idWithStyleRanges = idWithStyleRegex.matches(in: updatedSVGString, options: [], range: svgNSRange)
    
    
    //a. find IDs used
    guard idWithStyleRanges.count > 0 else {
        return .failure(SVGConversionError.idsNotFound)
    }
    
    print("**** Found IDS: \(idWithStyleRanges.count)");
    
    var allStyles = [StyleInfo]()
  
    for result in idWithStyleRanges {
        //b. add ids to array without the #
        let startIndex = updatedSVGString.index(updatedSVGString.startIndex, offsetBy: result.range.location)
        let endIndex = updatedSVGString.index(startIndex, offsetBy: result.range.length)
        
        let idWithStyleString = String(updatedSVGString[startIndex..<endIndex])
        let idWithStyleRange = NSRange(location: 0, length: idWithStyleString.utf16.count)
 
        
        //get id
        guard let idRange = idRegex.firstMatch(in: idWithStyleString, options: [], range: idWithStyleRange) else {
            return .failure(SVGConversionError.couldNotFindMatch(matchLocation: "id matching"))
        }
        let startIDIndex = idWithStyleString.index(idWithStyleString.startIndex, offsetBy: idRange.range.location + 1)
        let endIDIndex = idWithStyleString.index(startIDIndex, offsetBy: idRange.range.length - 1)
        let id = String(idWithStyleString[startIDIndex..<endIDIndex])
        
        //get style
        guard  let originalStyleRange = styleRegex.firstMatch(in: idWithStyleString, options: [], range: idWithStyleRange) else {
            return .failure(SVGConversionError.couldNotFindMatch(matchLocation: "style matching"))
        }
     
        let startStyleIndex = idWithStyleString.index(idWithStyleString.startIndex, offsetBy: originalStyleRange.range.location)
        let endStyleIndex = idWithStyleString.index(startStyleIndex, offsetBy: originalStyleRange.range.length)
        var style = String(idWithStyleString[startStyleIndex..<endStyleIndex])
       
        style.removeLast()
        style.removeFirst()
 
        let styleInfo = StyleInfo(id: id, style: style, idWithStyleRange: result.range)
        allStyles.append(styleInfo)
    }
    
    //remove style and Ids
    allStyles.reverse()
    for styleInfo in allStyles {
        guard let range = Range(styleInfo.idWithStyleRange, in: updatedSVGString) else {
            return .failure(SVGConversionError.couldNotConvertRangeToNSRange)
        }
        updatedSVGString.removeSubrange(range)
    }

    // update SVG body to contain style
    allStyles.forEach { styleInfo in
        let idInBody = "id=\"\(styleInfo.id)\""
        let idWithStyleInBody = "\(idInBody) style=\"\(styleInfo.style)\""
        updatedSVGString = updatedSVGString.replacingOccurrences(of: idInBody, with: idWithStyleInBody)
    }
   
    return .success(updatedSVGString)
}

func writeNewSVGFile(svgString: String, existingFilePath: String) -> Result<String, Error> {
    let pathComponents = existingFilePath.components(separatedBy: "/")
    
    //a. create new filename
    guard let newFilename = pathComponents.last?.replacingOccurrences(of: ".svg", with: "-updated.svg") else {
        return .failure(SVGConversionError.newFileName)
    }

    var newPathComponents = pathComponents.dropLast()
    newPathComponents.append(String(newFilename))
    let newPath = newPathComponents.joined(separator: "/")
    
    //b. create new filepath
    guard let outputURL = URL(string: "file://" + newPath) else {
        return .failure(SVGConversionError.createFile(filePath: newPath))
    }
    
    //c. convert string to data to write to file
    guard let data = svgString.data(using: String.Encoding.utf8) else {
        return .failure(SVGConversionError.convertingStringToData)
    }
    
    //d. write data to file
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
    let updatedSVGResult = changeIdsToInline(svgString: contents)
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
