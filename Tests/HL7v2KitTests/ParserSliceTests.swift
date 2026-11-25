// ParserSliceTests.swift
// The parser's splits as shared functions: each slice is a slice of its input, and the
// slices are what the parse is built from (P01 R4, #37).

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Parser slices")
struct ParserSliceTests {
    static let lineCases: [(String, [String], [String])] = [
        // text, lines under .lenient, lines under .strict
        ("A\rB\r", ["A", "B"], ["A", "B"]),
        ("A\rB", ["A", "B"], ["A", "B"]),
        ("A\r\nB\r\n", ["A", "B"], ["A", "\nB", "\n"]),
        ("A\nB\n", ["A", "B"], ["A\nB\n"]),
        ("A\r\rB\r", ["A", "", "B"], ["A", "", "B"]),
        ("A\n\rB", ["A", "", "B"], ["A\n", "B"]),
        ("A\r\r\nB", ["A", "", "B"], ["A", "", "\nB"]),
        ("", [], []),
        ("\rA", ["", "A"], ["", "A"]),
        ("\nA", ["", "A"], ["\nA"]),
        ("\r\nA", ["", "A"], ["", "\nA"]),
        ("\r", [""], [""]),
        ("\r\n", [""], ["", "\n"]),
        ("AB", ["AB"], ["AB"]),
        // Unchanged: the text replacement this supersedes also ended the line before a zero-width joiner.
        ("A\n\u{200D}B", ["A", "\u{200D}B"], ["A\n\u{200D}B"]),
        // Changed under .lenient (#37). The text replacement this supersedes missed a line feed
        // directly followed by a character that extends the one before it: a lone \n stayed in the
        // value, and the \n of a \r\n stayed at the start of the next line.
        ("A\n\u{0301}B", ["A", "\u{0301}B"], ["A\n\u{0301}B"]),
        ("A\n\u{200C}B", ["A", "\u{200C}B"], ["A\n\u{200C}B"]),
        ("A\r\n\u{0301}B", ["A", "\u{0301}B"], ["A", "\n\u{0301}B"]),
    ]

    @Test("Lines are split as the policy ends them, and each is a slice of the text")
    func lines() {
        for (text, lenient, strict) in Self.lineCases {
            let l = Parser.lineSlices(of: text, policy: .lenient)
            let s = Parser.lineSlices(of: text, policy: .strict)
            #expect(l.map(String.init) == lenient, "lenient \(text.debugDescription)")
            #expect(s.map(String.init) == strict, "strict \(text.debugDescription)")
            for slice in l + s {
                #expect(slice.startIndex >= text.startIndex && slice.endIndex <= text.endIndex)
                #expect(String(slice) == String(text[slice.startIndex..<slice.endIndex]))
            }
        }
        #expect(Parser.endsWithTerminator("A\r", policy: .strict))
        #expect(!Parser.endsWithTerminator("A\n", policy: .strict))
        #expect(Parser.endsWithTerminator("A\n", policy: .lenient))
        #expect(Parser.endsWithTerminator("A\r", policy: .lenient))
        #expect(Parser.endsWithTerminator("A\r\n", policy: .lenient))
        #expect(!Parser.endsWithTerminator("A", policy: .lenient))
    }

    @Test("Under the default preset a line feed before a combining mark ends its segment")
    func lineFeedBeforeCombiningMark() throws {
        // The text replacement this supersedes did not match a line feed directly followed by a
        // character that extends the one before it, so it stayed in NTE-3 and there were two segments.
        let wire = "MSH|^~\\&|APP|FAC|||20240101||ADT^A01|CTRL1|P|2.5.1\rNTE|1||one\n\u{0301}two\r"
        let message = try Parser().parse(wire)
        try #require(message.segments.count == 3)
        #expect(message.segments[2].segmentID.unicodeScalars.first == "\u{0301}")
    }

    @Test("A separator segment's field 1 is the message's field separator, whatever its line spells")
    func separatorSegmentFieldOne() throws {
        let wire = "MSH|^~\\&|APP|FAC|||20240101||ADT^A01|CTRL1|P|2.5.1\rBHS#^~\\&#X\r"
        let message = try Parser().parse(wire)
        #expect(message["BHS-1"] == "|")
    }

    @Test("Field slices: an ordinary line, a separator segment, a bare ID and a short line")
    func fields() throws {
        let e = EncodingCharacters.default
        let pid = "PID|1||X^Y~Z|"[...]
        let ordinary = try #require(Parser.fieldSlices(of: pid, encoding: e, separatorSegment: false))
        #expect(String(ordinary.id) == "PID")
        #expect(ordinary.fields.map(String.init) == ["1", "", "X^Y~Z", ""])
        let msh = "MSH|^~\\&|APP"[...]
        let header = try #require(Parser.fieldSlices(of: msh, encoding: e, separatorSegment: true))
        #expect(header.fields.map(String.init) == ["|", "^~\\&", "APP"])
        #expect(header.fields[0].startIndex == msh.index(msh.startIndex, offsetBy: 3))
        let bare = try #require(Parser.fieldSlices(of: "ZZZ"[...], encoding: e, separatorSegment: false))
        #expect(bare.fields.isEmpty)
        #expect(Parser.fieldSlices(of: "AB"[...], encoding: e, separatorSegment: false) == nil)
    }

    @Test("Repetition, component and subcomponent slices keep empty parts")
    func below() {
        let e = EncodingCharacters.default
        #expect(Parser.repetitionSlices(of: "A~~B"[...], encoding: e).map(String.init) == ["A", "", "B"])
        #expect(Parser.repetitionSlices(of: ""[...], encoding: e).map(String.init) == [""])
        #expect(Parser.componentSlices(of: "A^^B^"[...], encoding: e).map(String.init) == ["A", "", "B", ""])
        #expect(Parser.subcomponentSlices(of: "A&B\\T\\C"[...], encoding: e).map(String.init) == ["A", "B\\T\\C"])
    }

    @Test("A separator followed by a combining mark is data, not a delimiter")
    func combiningMark() {
        let e = EncodingCharacters.default
        let field = "A^\u{0301}B^C"[...]
        #expect(Parser.componentSlices(of: field, encoding: e).map(String.init) == ["A^\u{0301}B", "C"])
    }
}
