// SourceMapTests.swift
// Parser.sourceMap(of:): where in the input each parsed value sits (P01 R4, #37).

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Source map")
struct SourceMapTests {
    /// Every subcomponent of `message` with its location, in document order.
    static func leaves(of message: Message) -> [(WireLocation, Subcomponent)] {
        var result: [(WireLocation, Subcomponent)] = []
        var occurrence: [String: Int] = [:]
        for segment in message.segments {
            let id = segment.segmentID
            occurrence[id, default: 0] += 1
            for (f, field) in segment.fields.enumerated() where f >= 1 {
                for (r, repetition) in field.repetitions.enumerated() {
                    for (c, component) in repetition.components.enumerated() {
                        for (s, sub) in component.subcomponents.enumerated() {
                            result.append((WireLocation(segmentID: id, segmentIndex: occurrence[id] ?? 1,
                                                        fieldIndex: f, repetitionIndex: r + 1,
                                                        componentIndex: c + 1, subcomponentIndex: s + 1), sub))
                        }
                    }
                }
            }
        }
        return result
    }

    /// The bytes of `data` at `range`, decoded as the message's character set decodes them; nil
    /// when `range` is not inside `data` or cuts a character.
    static func text(_ data: Data, _ range: Range<Int>, _ encoding: CharacterEncoding) -> String? {
        guard range.lowerBound >= 0, range.upperBound <= data.count else { return nil }
        let bytes = data.subdata(in: (data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound))
        // Not `decode` under UTF-8: Foundation's drops a leading U+FEFF, which a value may start with.
        guard encoding == .utf8 else { return encoding.decode(bytes) }
        let decoded = String(decoding: bytes, as: UTF8.self)
        return decoded.utf8.elementsEqual(bytes) ? decoded : nil   // a cut character decodes as U+FFFD
    }

    /// Whether `text` is `expected` byte for byte: `String ==` takes two spellings of a character as one.
    static func same(_ text: String?, _ expected: String) -> Bool {
        text?.utf8.elementsEqual(expected.utf8) == true
    }

    /// The place `indices` names (field, repetition, component, subcomponent, as many as given) in
    /// occurrence `n` of segment `id`.
    static func place(_ id: String, _ n: Int, _ indices: [Int]) -> WireLocation {
        func at(_ k: Int) -> Int? { k < indices.count ? indices[k] : nil }
        return WireLocation(segmentID: id, segmentIndex: n, fieldIndex: at(0), repetitionIndex: at(1),
                            componentIndex: at(2), subcomponentIndex: at(3))
    }

    /// The map has a range for the value at `parent` and for each of its `count` children, and none
    /// for a child after the last. The bytes from the parent's start to child 1 read `lead`, those
    /// between child k - 1 and child k read `gap(k)`, and the parent ends where its last child
    /// ends, or where `lead` ends when it has none.
    static func checkChildren(_ map: SourceMap, _ data: Data, _ encoding: CharacterEncoding, _ id: String, _ n: Int,
                              _ parent: [Int], count: Int, lead: String, gap: (Int) -> String, _ name: String) {
        let label = "\(name) \(id)[\(n)] \(parent)"
        guard let outer = map.range(of: place(id, n, parent)) else {
            Issue.record("\(label): no range")
            return
        }
        // The text from byte `lower` to byte `upper`; nil when they are out of order or outside the parent.
        func read(_ lower: Int, _ upper: Int) -> String? {
            outer.lowerBound <= lower && lower <= upper && upper <= outer.upperBound
                ? text(data, lower..<upper, encoding) : nil
        }
        var end = outer.lowerBound
        for k in stride(from: 1, through: count, by: 1) {
            guard let inner = map.range(of: place(id, n, parent + [k])) else {
                Issue.record("\(label) child \(k): no range")
                continue
            }
            #expect(same(read(end, inner.lowerBound), k == 1 ? lead : gap(k)), "\(label) before child \(k)")
            end = inner.upperBound
        }
        #expect(count == 0 ? same(read(end, outer.upperBound), lead) : end == outer.upperBound, "\(label) end")
        #expect(map.range(of: place(id, n, parent + [count + 1])) == nil, "\(label) child \(count + 1)")
    }

    static func check(_ data: Data, options: ParserOptions, _ name: String) throws {
        let parser = Parser(options: options)
        let message = try parser.parse(data)
        let map = try parser.sourceMap(of: data)
        let encoding = message.characterEncoding
        let delimiters = message.encodingCharacters
        let separator = String(delimiters.fieldSeparator)
        // The shape: the map has every value the parse has and no other, each child where the
        // one before it ends plus one delimiter, and each parent ending where its last child ends.
        var occurrence: [String: Int] = [:]
        var end = 0
        for segment in message.segments {
            let id = segment.segmentID
            occurrence[id, default: 0] += 1
            let n = occurrence[id] ?? 1
            let line = map.range(of: place(id, n, []))
            #expect(line.map { $0.lowerBound >= end && Self.text(data, $0, encoding)?.utf8.starts(with: id.utf8) == true }
                    == true, "\(name) \(id)[\(n)]")
            end = line?.upperBound ?? end
            let fields = max(segment.fields.count - 1, 0)
            // A separator segment's field 1 is the line's fourth character, with field 2 right after it.
            let separatorSegment = Parser.isSeparatorSegment(id)
            checkChildren(map, data, encoding, id, n, [], count: fields,
                          lead: separatorSegment || fields == 0 ? id : id + separator,
                          gap: { separatorSegment && $0 == 2 ? "" : separator }, name)
            for (f, field) in segment.fields.enumerated() where f >= 1 {
                checkChildren(map, data, encoding, id, n, [f], count: field.repetitions.count, lead: "",
                              gap: { _ in String(delimiters.repetitionSeparator) }, name)
                for (r, repetition) in field.repetitions.enumerated() {
                    checkChildren(map, data, encoding, id, n, [f, r + 1], count: repetition.components.count,
                                  lead: "", gap: { _ in String(delimiters.componentSeparator) }, name)
                    for (c, component) in repetition.components.enumerated() {
                        checkChildren(map, data, encoding, id, n, [f, r + 1, c + 1],
                                      count: component.subcomponents.count, lead: "",
                                      gap: { _ in String(delimiters.subcomponentSeparator) }, name)
                    }
                }
            }
        }
        for (id, count) in occurrence {
            #expect(map.range(of: place(id, count + 1, [])) == nil, "\(name) \(id)[\(count + 1)]")
        }
        for (location, sub) in Self.leaves(of: message) {
            // The text the parse read: its wire text when it held the escape character, else its
            // value (MSH-1 and MSH-2 are their literal text). Not `EscapeSequences.wireForm`, which
            // re-escapes a control character the input holds bare (a kept line feed as `\X0A\`).
            var wire = sub.wire?.text ?? sub.value
            // The parse gives field 1 of MSH, BHS and FHS the message's separator; the wire holds
            // the line's own fourth character, which a BHS or FHS line may spell otherwise.
            if Parser.isSeparatorSegment(location.segmentID), location.fieldIndex == 1,
               let line = map.range(of: place(location.segmentID, location.segmentIndex, [])),
               let lineText = Self.text(data, line, encoding) {
                wire = String(lineText.dropFirst(3).prefix(1))
            }
            let range = map.range(of: location)
            #expect(range != nil, "\(name) \(location)")
            if let range {
                #expect(same(Self.text(data, range, encoding), wire), "\(name) \(location)")
            }
        }
        checkLocations(map, data, message, name)
    }

    @Test("Every value of every valid fixture sits where the map says, under both presets")
    func agreement() throws {
        for url in try FixtureCorpus.validFixtureURLs() {
            let data = try Data(contentsOf: url)
            try Self.check(data, options: .default, url.lastPathComponent)
            if (try? Parser(options: .strict).parse(data)) != nil {
                try Self.check(data, options: .strict, url.lastPathComponent + " strict")
            }
        }
    }

    static let msh = "MSH|^~\\&|APP|FAC|RCV|FAC|20260101120000||ADT^A01^ADT_A01|CTRL1|P|2.5.1"

    @Test("MSH-1, MSH-2 and MSH-3; levels; an empty trailing field; absent values; a Data slice")
    func header() throws {
        let data = Data((Self.msh + "\rPID|1||MRN12345^^^HOSP&1.2&ISO~X||\r").utf8)
        let map = try Parser().sourceMap(of: data)
        func at(_ id: String, _ f: Int? = nil, _ r: Int? = nil, _ c: Int? = nil, _ s: Int? = nil) -> Range<Int>? {
            map.range(of: WireLocation(segmentID: id, segmentIndex: 1, fieldIndex: f, repetitionIndex: r,
                                       componentIndex: c, subcomponentIndex: s))
        }
        #expect(at("MSH", 1) == 3..<4)                              // MSH-1: the fourth character, `|`
        #expect(at("MSH", 2) == 4..<8)                              // MSH-2: `^~\&`, one value
        #expect(at("MSH", 2, 1, 1, 1) == 4..<8)                     // MSH-2 has no split below it
        #expect(at("MSH", 3) == 9..<12)                             // MSH-3: `APP`
        #expect(at("MSH") == 0..<Self.msh.utf8.count)               // the segment: its line, no terminator
        let pid = Self.msh.utf8.count + 1
        #expect(at("PID") == pid..<(data.count - 1))                // the PID line without its `\r`
        #expect(at("PID", 3) == (pid + 7)..<(pid + 32))             // PID-3: `MRN12345^^^HOSP&1.2&ISO~X`
        #expect(at("PID", 3, 2) == (pid + 31)..<(pid + 32))         // PID-3's second repetition: `X`
        #expect(at("PID", 3, 1, 4, 2) == (pid + 23)..<(pid + 26))   // PID-3.4.2: `1.2`
        #expect(at("PID", 2) == (pid + 6)..<(pid + 6))              // PID-2: empty, between `||`
        #expect(at("PID", 5) == (pid + 34)..<(pid + 34))            // PID-5: the empty trailing field
        #expect(at("PID", 6) == nil)                                // PID-6: absent
        #expect(at("PV1") == nil)                                   // no such segment
        #expect(at("MSH", 1, 2) == nil)                             // MSH-1 has one repetition
        #expect(at("MSH", 2, 1, 2) == nil)                          // MSH-2 is not split into components
        for bad in [0, -1, Int.min] {
            #expect(map.range(of: WireLocation(segmentID: "PID", segmentIndex: bad)) == nil)
            #expect(at("PID", bad) == nil)
            #expect(at("PID", 3, bad) == nil)
            #expect(at("PID", 3, 1, bad) == nil)
            #expect(at("PID", 3, 1, 4, bad) == nil)
        }
        #expect(map.text == String(decoding: data, as: UTF8.self))
        // A slice of a larger Data: offsets count from the slice's first byte, not from zero.
        let slice = (Data("XY".utf8) + data).dropFirst(2)
        #expect(slice.startIndex == 2)
        try Self.check(slice, options: .default, "slice")
        #expect(try Parser().sourceMap(of: slice).range(of: WireLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 3)) == 9..<12)
    }

    @Test("Header lines inside a message: a later MSH, an MSHX line, BHS, bare lines, and FHS with its own separator")
    func headerLines() throws {
        let tail = "FHS#^~\\&#F\r"
        let data = Data((Self.msh + "\rMSH|^~\\&|X|Y\rMSHX|1|2\rBHS|^~\\&|B\rFHS|^~\\&\rBHS\rZZZ\r" + tail).utf8)
        try Self.check(data, options: .default, "header lines")
        let map = try Parser().sourceMap(of: data)
        // The last FHS spells `#` in FHS-1: the map covers it, though the parse reads `|` there.
        let hash = data.count - tail.utf8.count + 3
        #expect(map.range(of: WireLocation(segmentID: "FHS", segmentIndex: 2, fieldIndex: 1)) == hash..<(hash + 1))
        #expect(map.range(of: WireLocation(segmentID: "MSHX", segmentIndex: 1, fieldIndex: 2)) != nil)
        #expect(map.range(of: WireLocation(segmentID: "MSH", segmentIndex: 2, fieldIndex: 2, repetitionIndex: 1,
                                           componentIndex: 2)) == nil)   // the later MSH-2 is one value
    }

    @Test("ISO 8859-1, four-byte UTF-8, a byte-order mark, custom delimiters and an escape as written")
    func encodings() throws {
        let latin = Array((Self.msh + "||||||8859/1\rPID|1||M").utf8) + [0xFC] + Array("ller^X\r".utf8)
        try Self.check(Data(latin), options: .default, "latin1")
        let utf8 = Data((Self.msh + "||||||UNICODE UTF-8\rPID|1||A\u{1F600}B^C\r").utf8)
        try Self.check(utf8, options: .default, "utf8")
        let emoji = try #require(utf8.firstIndex(of: 0xF0))                // the first of U+1F600's four bytes
        #expect(Self.text(utf8, emoji..<(emoji + 2), .utf8) == nil)       // a range that cuts it reads nothing
        try Self.check(Data([0xEF, 0xBB, 0xBF]) + utf8, options: .default, "bom")
        // Foundation's UTF-8 decode drops a second mark the parse does not strip.
        try Self.check(Data([0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF]) + utf8, options: .default, "two marks")
        try Self.check(Data((Self.msh + "||||||UNICODE UTF-8\rNTE|1||\u{FEFF}x\r").utf8), options: .default, "U+FEFF")
        let bom = try Parser().sourceMap(of: Data([0xEF, 0xBB, 0xBF]) + utf8)
        #expect(bom.range(of: WireLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 1)) == 6..<7)
        let custom = Data("MSH#$~\\&#APP#FAC#RCV#FAC#20260101120000##ADT$A01$ADT_A01#CTRL1#P#2.5.1\rNTE#1##a\\F\\b\r".utf8)
        try Self.check(custom, options: .default, "custom")
        let amp = Data((Self.msh + "\rOBX|1|ST|X||A&B\rOBX|2|ST|X||A&B^C\r").utf8)
        try Self.check(amp, options: .default, "ampersand")
    }

    @Test("Line endings: CRLF under .lenient, a blank line, a kept line feed under .strict")
    func lineEndings() throws {
        let crlf = Data((Self.msh + "\r\n\r\nPID|1||X\r\n").utf8)
        try Self.check(crlf, options: .default, "crlf")
        let map = try Parser().sourceMap(of: crlf)
        let pid = Self.msh.utf8.count + 4
        #expect(map.range(of: WireLocation(segmentID: "PID", segmentIndex: 1)) == pid..<(pid + 8))
        let open = Data((Self.msh + "\r\nPID|1||X").utf8)
        try Self.check(open, options: .default, "no final terminator")
        #expect(try Parser().sourceMap(of: open).range(of: WireLocation(segmentID: "PID", segmentIndex: 1))
                == (open.count - 8)..<open.count)
        let kept = Data((Self.msh + "\rNTE|1||one\ntwo\r").utf8)
        try Self.check(kept, options: ParserOptions(lineTerminator: .strict), "kept line feed")
    }

    @Test("It throws what parse throws")
    func errors() {
        #expect(throws: ParseError.emptyInput) { _ = try Parser().sourceMap(of: Data()) }
        #expect(throws: ParseError.missingMSH) { _ = try Parser().sourceMap(of: Data("PID|1\r".utf8)) }
    }

    @Test("A location from an issue, and a location as a path")
    func conversions() throws {
        let issue = IssueLocation(segmentID: "PID", segmentIndex: 1, fieldIndex: 3, repetitionIndex: 2,
                                  componentIndex: 4, subcomponentIndex: nil)
        let place = WireLocation(issue)
        #expect(place == WireLocation(segmentID: "PID", segmentIndex: 1, fieldIndex: 3, repetitionIndex: 2, componentIndex: 4))
        #expect(place.path?.description == "PID[1]-3~2.4")
        let noRepetition = WireLocation(IssueLocation(segmentID: "PID", segmentIndex: 1, fieldIndex: 3, componentIndex: 4))
        #expect(noRepetition.repetitionIndex == 1)
        #expect(WireLocation(segmentID: "PID", segmentIndex: 2).path?.description == "PID[2]")
        #expect(WireLocation(segmentID: "PID", segmentIndex: 2).path?.isSegmentOnly == true)
        // A subcomponent without a component names the field, as `range(of:)` reads it.
        #expect(WireLocation(segmentID: "PID", segmentIndex: 1, fieldIndex: 3, subcomponentIndex: 2).path?.description == "PID[1]-3")
    }

    @Test("One parse: parseWithSourceMap gives parse's message and sourceMap(of:)'s map; scanning bytes changes no range")
    func parseWithSourceMapAgrees() throws {
        for url in try FixtureCorpus.validFixtureURLs() {
            let data = try Data(contentsOf: url)
            let parser = Parser()
            let both = try parser.parseWithSourceMap(data)
            #expect(both.message == (try parser.parse(data)), "\(url.lastPathComponent)")
            #expect(both.sourceMap.segments == (try parser.sourceMap(of: data)).segments, "\(url.lastPathComponent)")
            let characters = try SourceMap(mapping: data, encoding: both.message.encodingCharacters,
                                           policy: parser.options.lineTerminator, scanBytes: false)
            #expect(characters.segments == both.sourceMap.segments, "\(url.lastPathComponent)")
            // After a byte-order mark every range is three bytes on, by either route.
            let marked = Data([0xEF, 0xBB, 0xBF]) + data
            let scanned = try parser.sourceMap(of: marked).segments
            #expect(scanned.first?.range.lowerBound == 3, "\(url.lastPathComponent)")
            #expect(scanned == (try SourceMap(mapping: marked, encoding: both.message.encodingCharacters,
                                              policy: parser.options.lineTerminator, scanBytes: false)).segments,
                    "\(url.lastPathComponent) after a byte-order mark")
        }
    }
}
