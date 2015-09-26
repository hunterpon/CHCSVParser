//
//  FieldParser.swift
//  CHCSVParser
//
//  Created by Dave DeLong on 9/19/15.
//
//

import Foundation

struct FieldParser {
    
    func parse(stream: PeekingGenerator<Character>, configuration: CSVParserConfiguration, line: UInt, index: UInt) throws -> ParsingDisposition {
        let peek = stream.peek()
        
        // there are more characters
        
        if peek == nil || peek == configuration.delimiter || peek?.isNewline == true {
            return configuration.onReadField?("", index, stream.progress()) ?? .Continue
        }
        
        // consume the leading whitespace
        let leadingWS = parseWhitespace(stream, configuration: configuration)
        
        let field: String
        if stream.peek() == Character.DoubleQuote {
            // parse an escaped field
            field = try parseEscapedField(stream, configuration: configuration, line: line, index: index)
            
        } else if configuration.recognizeLeadingEqualSign && stream.peek() == Character.Equal && stream.peek(1) == Character.DoubleQuote {
            //parse an escaped field
            field = try parseEscapedField(stream, configuration: configuration, line: line, index: index)
            
        } else {
            // parse an unescaped field
            field = try parseUnescapedField(stream, configuration: configuration, line: line, index: index)
        }
        
        let trailingWS = parseWhitespace(stream, configuration: configuration)
        
        // restore the whitespace around the field
        
        let final = configuration.trimWhitespace ? field.trim() : leadingWS + field + trailingWS
        let expectedDisposition = configuration.onReadField?(final, index, stream.progress()) ?? .Continue
        
        if stream.peek() == nil { return .Cancel }
        return expectedDisposition
    }
    
    func parseWhitespace(stream: PeekingGenerator<Character>, configuration: CSVParserConfiguration) -> String {
        var w = ""
        while let peek = stream.peek() where peek.isWhitespace && peek != configuration.delimiter {
            w.append(peek)
            stream.next()
        }
        return w
    }
    
    func parseUnescapedField(stream: PeekingGenerator<Character>, configuration: CSVParserConfiguration, line: UInt, index: UInt) throws -> String {
        var field = ""
        var sanitized = ""
        
        var isBackslashEscaped = false
        while let next = stream.peek() {
            if isBackslashEscaped == false {
                if next == Character.Backslash && configuration.recognizeBackslashAsEscape {
                    field.append(next)
                    stream.next()
                    isBackslashEscaped = true
                } else if next.isNewline || next == configuration.delimiter {
                    break
                } else {
                    field.append(next)
                    sanitized.append(next)
                    stream.next()
                }
            } else {
                isBackslashEscaped = false
                field.append(next)
                sanitized.append(next)
                stream.next()
            }
        }
        
        if isBackslashEscaped == true {
            throw CSVError(kind: .IncompleteField, line: line, field: index, progress: stream.progress())
        }
        
        let next = stream.peek()
        if next == nil || next == configuration.delimiter || next?.isNewline == true {
            return configuration.sanitizeFields ? sanitized : field
        }
        
        fatalError("Implementation flaw; Unexpectedly finished parsing unescaped field")
    }
    
    func parseEscapedField(stream: PeekingGenerator<Character>, configuration: CSVParserConfiguration, line: UInt, index: UInt) throws -> String {
        var raw = ""
        var sanitized = ""
        
        if configuration.recognizeLeadingEqualSign && stream.peek() == Character.Equal {
            stream.next()
            raw.append(Character.Equal)
        }
        
        guard let next = stream.next() where next == Character.DoubleQuote else {
            fatalError("Unexpected character opening escaped field")
        }
        
        raw.append(Character.DoubleQuote)
        var isBackslashEscaped = false
        
        while let next = stream.peek() {
            if isBackslashEscaped == false {
                
                if next == Character.Backslash && configuration.recognizeBackslashAsEscape {
                    isBackslashEscaped = true
                    stream.next()
                    raw.append(next)
                } else if next == Character.DoubleQuote && stream.peek(1) == Character.DoubleQuote {
                    sanitized.append(Character.DoubleQuote)
                    raw.append(Character.DoubleQuote); raw.append(Character.DoubleQuote)
                    stream.next()
                    stream.next()
                } else if next == Character.DoubleQuote {
                    // quote that is NOT followed by another quote
                    // this is the closing field quote
                    break
                } else {
                    raw.append(next)
                    sanitized.append(next)
                    stream.next()
                }
                
            } else {
                raw.append(next)
                sanitized.append(next)
                
                isBackslashEscaped = false
                stream.next() // consume the character
            }
        }
        
        guard isBackslashEscaped == false else {
            throw CSVError(kind: .IncompleteField, line: line, field: index, progress: stream.progress())
        }
        
        guard stream.peek() == Character.DoubleQuote else {
            throw CSVError(kind: .UnexpectedFieldTerminator, line: line, field: index, progress: stream.progress())
        }
        
        raw.append(Character.DoubleQuote)
        stream.next()
        
        return configuration.sanitizeFields ? sanitized : raw
    }
}
