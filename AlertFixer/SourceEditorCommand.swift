//
//  SourceEditorCommand.swift
//  AlertFixer
//
//  Created by Shawn Roller on 2/14/18.
//  Copyright © 2018 Shawn Roller. All rights reserved.
//

/*
    Requires that UIAlertView+Blocks, UIAlertController+Blocks, and UIAlertController+Expanded are used in the project
    AlertFixer will only find and replace the [UIAlertView showWithTitle:message:cancelButtonTitle:otherButtonTitles:tapBlock:] method with the corresponding UIAlertController+Blocks method.
    The developer must test and troubleshoot the replacements that are made, as it may not provide a 1:1 converion
*/

import Foundation
import XcodeKit

// Extend string with convenience functions
extension String {
    func index(of string: String, options: CompareOptions = .literal) -> Index? {
        return range(of: string, options: options)?.lowerBound
    }
    func endIndex(of string: String, options: CompareOptions = .literal) -> Index? {
        return range(of: string, options: options)?.upperBound
    }
}

class SourceEditorCommand: NSObject, XCSourceEditorCommand {
    
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void ) -> Void {
        replaceAlerts(invocation: invocation) { (_) in
            completionHandler(nil)
        }
    }
    
    private func replaceAlerts(invocation: XCSourceEditorCommandInvocation, completion: @escaping (Bool) -> Void) {
        for (lineIndex, line) in invocation.buffer.lines.enumerated() {
            guard let theLine = line as? String, theLine.count > 0 else { continue }
            let (containsAlert, containsTapBlock) = lineContainsAlert(line: theLine)
            if containsAlert {
                if containsTapBlock {
                    // Capture the tap block
                    let (newLine, endLineIndex) = getAlertControllerStringWithTapBlock(from: theLine, lineIndex: lineIndex, in: invocation.buffer)
                    // Update the buffer with the new line
                    let range = Range(uncheckedBounds: (lower: lineIndex, upper: endLineIndex + 1))
                    let indexSet = IndexSet(integersIn: range)
                    invocation.buffer.lines.removeObjects(at: indexSet)
                    invocation.buffer.lines.insert(newLine, at: lineIndex)
                }
                else {
                    // No tap block is present
                    let newLine = getAlertControllerString(from: theLine)
                    invocation.buffer.lines[lineIndex] = newLine
                }
                replaceAlerts(invocation: invocation, completion: completion)
                return
            }
        }
        completion(true)
    }
    
    private func lineContainsAlert(line: String) -> (containsAlert: Bool, containsTapBlock: Bool) {
        var containsAlert = false
        var containsTapBlock = false
        
        // Determine if the line contains an alert view
        do {
            let pattern = "^\\s*(\\[UIAlertView showWithTitle)(.*|\\s*)(message:)(.*|\\s*)(cancelButtonTitle:)(.*|\\s*)(otherButtonTitles:)(.*|\\s*)(tapBlock:)(.*|\\s*)"
            let regex = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
            let range = NSMakeRange(0, line.count)
            let matches = regex.matches(in: line, options: [], range: range)
            containsAlert = matches.count > 0
        }
        catch {
            fatalError(error.localizedDescription)
        }
        
        if containsAlert {
            // Determine if the alert view contains a tap block
            let tapBlockIndex = line.index(of: "{")
            containsTapBlock = tapBlockIndex != nil
        }
        
        return (containsAlert, containsTapBlock)
    }
    
    private func getTitle(from line: String) -> String {
        var title = ""
        guard let startIndex = line.endIndex(of: "showWithTitle:") else { return title }
        guard let endIndex = line.index(of: " message:") else { return title }
        title = String(line[startIndex..<endIndex])
        return title
    }
    
    private func getMessage(from line: String) -> String {
        var message = ""
        guard let startIndex = line.endIndex(of: " message:") else { return message }
        guard let endIndex = line.index(of: " cancelButtonTitle:") else { return message }
        message = String(line[startIndex..<endIndex])
        return message
    }
    
    private func getCancelButtonTitle(from line: String) -> String {
        var cancelButtonTitle = ""
        guard let startIndex = line.endIndex(of: " cancelButtonTitle:") else { return cancelButtonTitle }
        guard let endIndex = line.index(of: " otherButtonTitles:") else { return cancelButtonTitle }
        cancelButtonTitle = String(line[startIndex..<endIndex])
        return cancelButtonTitle
    }
    
    private func getOtherButtonTitles(from line: String) -> String {
        var otherButtonTitles = ""
        guard let startIndex = line.endIndex(of: " otherButtonTitles:") else { return otherButtonTitles }
        guard let endIndex = line.index(of: " tapBlock:") else { return otherButtonTitles }
        otherButtonTitles = String(line[startIndex..<endIndex])
        return otherButtonTitles
    }
    
    private func getAlertControllerString(from line: String) -> String {
        var newLine = ""
        
        // Preserve the leading spaces
        guard let firstCharacterIndex = line.index(of: "[") else { return newLine }
        let startIndex = line.startIndex
        let leadingSpace = line[startIndex..<firstCharacterIndex]
        
        // Get the key elements to create a new UIAlertController
        let title = getTitle(from: line)
        let message = getMessage(from: line)
        let cancelButtonTitle = getCancelButtonTitle(from: line)
        let otherButtonTitles = getOtherButtonTitles(from: line)
        
        // Construct a new obj-c line as an alert controller
        newLine = "\(leadingSpace)[UIAlertController showAlertInViewController:self withTitle:\(title) message:\(message) cancelButtonTitle:\(cancelButtonTitle) destructiveButtonTitle:nil otherButtonTitles:\(otherButtonTitles) tapBlock:nil];"
        
        return newLine
    }
    
    private func getAlertControllerStringWithTapBlock(from line: String, lineIndex: Int, in buffer: XCSourceTextBuffer) -> (newLine: String, endLineIndex: Int) {
        var newLine = ""
        
        // Preserve the leading spaces
        guard let firstCharacterIndex = line.index(of: "[") else { return (newLine, lineIndex) }
        let startIndex = line.startIndex
        let leadingSpace = line[startIndex..<firstCharacterIndex]
        
        // Get the line that completes the tap block
        guard let lines = buffer.lines as? [String] else { return (newLine, lineIndex) }
        let endingLine = getEndingLineIndex(startIndex: lineIndex, leadingSpaces: leadingSpace.count, lines: lines)
        
        // Get all the lines between the start and end of the block
        let tapBlock = getLines(between: lineIndex, and: endingLine, from: lines)
        
        // Get the key elements to create a new UIAlertController
        let title = getTitle(from: line)
        let message = getMessage(from: line)
        let cancelButtonTitle = getCancelButtonTitle(from: line)
        let otherButtonTitles = getOtherButtonTitles(from: line)
        
        newLine = """
        \(leadingSpace)[UIAlertController showAlertInViewController:self withTitle:\(title) message:\(message) cancelButtonTitle:\(cancelButtonTitle) destructiveButtonTitle:nil otherButtonTitles:\(otherButtonTitles) tapBlock:^(UIAlertController * _Nonnull alertView, UIAlertAction * _Nonnull action, NSInteger buttonIndex) {
        \(tapBlock)\(leadingSpace)}];
        """
        
        return (newLine, endingLine)
    }
    
    private func getEndingLineIndex(startIndex: Int, leadingSpaces: Int, lines: [String]) -> Int {
        var endingLineIndex = 0
        
        for (index, line) in lines.enumerated() {
            guard index > startIndex else { continue }
            guard line.count > 0 else { continue }
            do {
                // Find the next line that ends a block and has the same indent level as the alertView
                let pattern = "^\\s{\(leadingSpaces)}\\}];"
                let regex = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
                let range = NSMakeRange(0, line.count)
                let matches = regex.matches(in: line, options: [], range: range)
                if matches.count > 0 {
                    endingLineIndex = index
                    break
                }
            }
            catch {
                fatalError(error.localizedDescription)
            }
        }
        return endingLineIndex
    }
    
    private func getLines(between startLine: Int, and endLine: Int, from lines: [String]) -> String {
        var tapBlock = ""
        
        for (index, line) in lines.enumerated() {
            guard index > startLine else { continue }
            guard index < endLine else { break }
            tapBlock += line
        }
        
        return tapBlock
    }
    
}

