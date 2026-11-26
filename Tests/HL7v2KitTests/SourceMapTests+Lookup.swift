// SourceMapTests+Lookup.swift
// SourceMap.location(at:) and utf16Range(_:): from a byte to its value, and UTF-16 offsets (P01 R4, #37).

import Foundation
import Testing
import HL7v2Kit

extension SourceMapTests {
    /// `location(at:)` at every byte of `data`, and one before and one past it, is the deepest value
    /// of `message` whose `range(of:)` holds the byte, and nil where none does: so a byte of a
    /// segment the parse does not have answers nil.
    static func checkLocations(_ map: SourceMap, _ data: Data, _ message: Message, _ name: String) {
        // Each value marks its bytes, children after their parent, so a byte ends holding the deepest.
        var deepest = [WireLocation?](repeating: nil, count: data.count)
        func mark(_ id: String, _ n: Int, _ indices: [Int]) {
            let location = place(id, n, indices)
            for byte in map.range(of: location)?.clamped(to: 0..<data.count) ?? 0..<0 { deepest[byte] = location }
        }
        var occurrence: [String: Int] = [:]
        for segment in message.segments {
            let id = segment.segmentID
            occurrence[id, default: 0] += 1
            let n = occurrence[id] ?? 1
            mark(id, n, [])
            for (f, field) in segment.fields.enumerated() where f >= 1 {
                mark(id, n, [f])
                for (r, repetition) in field.repetitions.enumerated() {
                    mark(id, n, [f, r + 1])
                    for (c, component) in repetition.components.enumerated() {
                        mark(id, n, [f, r + 1, c + 1])
                        for s in component.subcomponents.indices { mark(id, n, [f, r + 1, c + 1, s + 1]) }
                    }
                }
            }
        }
        for byte in -1...data.count {
            let expected = deepest.indices.contains(byte) ? deepest[byte] : nil
            let found = map.location(at: byte)
            if found != expected {   // the first difference only, not one issue per byte
                let wanted = String(describing: expected)
                Issue.record("\(name) byte \(byte): location(at:) \(String(describing: found)), deepest \(wanted)")
                return
            }
        }
    }

    @Test("Round trip: the location at the start of every non-empty leaf is that leaf")
    func roundTrip() throws {
        for url in try FixtureCorpus.validFixtureURLs() {
            let data = try Data(contentsOf: url)
            let message = try Parser().parse(data)
            let map = try Parser().sourceMap(of: data)
            for (location, _) in Self.leaves(of: message) {
                guard let range = map.range(of: location), !range.isEmpty else { continue }
                #expect(map.location(at: range.lowerBound) == location, "\(url.lastPathComponent) \(location)")
                #expect(map.location(at: range.upperBound - 1) == location, "\(url.lastPathComponent) \(location)")
            }
        }
    }

    @Test("A delimiter answers the value that encloses it; a terminator answers nothing")
    func delimiters() throws {
        let data = Data((Self.msh + "\rPID|1||A^B&C~D\r").utf8)
        let map = try Parser().sourceMap(of: data)
        let pid = Self.msh.utf8.count + 1
        func place(_ f: Int? = nil, _ r: Int? = nil, _ c: Int? = nil, _ s: Int? = nil) -> WireLocation {
            WireLocation(segmentID: "PID", segmentIndex: 1, fieldIndex: f, repetitionIndex: r, componentIndex: c, subcomponentIndex: s)
        }
        #expect(map.location(at: pid) == place())                   // P of the segment ID
        #expect(map.location(at: pid + 3) == place())               // the field separator after PID
        #expect(map.location(at: pid + 4) == place(1, 1, 1, 1))     // 1
        #expect(map.location(at: pid + 7) == place(3, 1, 1, 1))     // A
        #expect(map.location(at: pid + 8) == place(3, 1))           // ^ between components
        #expect(map.location(at: pid + 10) == place(3, 1, 2))       // & between subcomponents
        #expect(map.location(at: pid + 12) == place(3))             // ~ between repetitions
        #expect(map.location(at: pid + 13) == place(3, 2, 1, 1))    // D
        #expect(map.location(at: pid - 1) == nil)                   // the terminator after MSH
        #expect(map.location(at: data.count) == nil)
        #expect(map.location(at: -1) == nil)
        #expect(map.location(at: 3) == WireLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 1,
                                                    repetitionIndex: 1, componentIndex: 1, subcomponentIndex: 1))
        let bare = Data((Self.msh + "\rZZZ\r").utf8)                // a segment with no fields is its ID
        #expect(try Parser().sourceMap(of: bare).location(at: pid + 2) == WireLocation(segmentID: "ZZZ", segmentIndex: 1))
    }

    @Test("UTF-16 offsets: ISO 8859-1, four-byte UTF-8, a byte-order mark, a bound inside a character")
    func utf16() throws {
        func utf16Text(_ map: SourceMap, _ range: Range<Int>) -> String {
            let units = Array(map.text.utf16)[map.utf16Range(range)]
            return String(decoding: units, as: UTF16.self)
        }
        let latin = Data(Array((Self.msh + "||||||8859/1\rPID|1||M").utf8) + [0xFC] + Array("ller^X\r".utf8))
        let latinMap = try Parser().sourceMap(of: latin)
        let name = try #require(latinMap.range(of: WireLocation(segmentID: "PID", segmentIndex: 1, fieldIndex: 3,
                                                                repetitionIndex: 1, componentIndex: 1)))
        #expect(utf16Text(latinMap, name) == "M\u{FC}ller")
        let utf8 = Data((Self.msh + "||||||UNICODE UTF-8\rPID|1||A\u{1F600}B^C\r").utf8)
        let mark = Data([0xEF, 0xBB, 0xBF])
        for data in [utf8, mark + utf8, mark + mark + utf8] {
            let map = try Parser().sourceMap(of: data)
            let first = try #require(map.range(of: WireLocation(segmentID: "PID", segmentIndex: 1, fieldIndex: 3,
                                                                repetitionIndex: 1, componentIndex: 1)))
            let second = try #require(map.range(of: WireLocation(segmentID: "PID", segmentIndex: 1, fieldIndex: 3,
                                                                 repetitionIndex: 1, componentIndex: 2)))
            #expect(utf16Text(map, first) == "A\u{1F600}B")
            #expect(utf16Text(map, second) == "C")
            // A bound inside the four bytes of U+1F600 moves back to its first byte.
            let emoji = first.lowerBound + 1
            #expect(utf16Text(map, (emoji + 2)..<(emoji + 4)) == "\u{1F600}")
            #expect(map.utf16Range((emoji + 1)..<(emoji + 3)) == map.utf16Range(emoji..<emoji))
            // A byte of a mark answers nothing; bounds in a mark or outside the input are clamped.
            let marks = data.count - utf8.count
            for byte in 0..<marks { #expect(map.location(at: byte) == nil) }
            #expect(map.location(at: marks) == WireLocation(segmentID: "MSH", segmentIndex: 1))
            #expect(map.utf16Range(-4..<(data.count + 4)) == 0..<map.text.utf16.count)
        }
    }

    @Test("Two messages in one Data map as parse reads them: one message, the second header MSH[2]")
    func twoMessagesInOneData() throws {
        let first = "MSH|^~\\&|SND|FAC|RCV|FAC|20260101120000||ADT^A01^ADT_A01|M1|P|2.5.1\rPID|1||MRN12345\r"
        let second = "MSH|^~\\&|SND|FAC|RCV|FAC|20260101120100||ADT^A08^ADT_A01|M2|P|2.5.1\rPID|1||MRN67890\r"
        let data = Data((first + second).utf8)
        let (message, map) = try Parser().parseWithSourceMap(data)
        #expect(message.segments.map(\.segmentID) == ["MSH", "PID", "MSH", "PID"])
        let header = try #require(map.range(of: WireLocation(segmentID: "MSH", segmentIndex: 2)))
        #expect(header.lowerBound == first.utf8.count)
        let controlID = try #require(map.range(of: WireLocation(segmentID: "MSH", segmentIndex: 2, fieldIndex: 10)))
        #expect(String(decoding: data[controlID], as: UTF8.self) == "M2")

        // Split first, and each message maps on its own; an offset in the input is the
        // range's lower bound plus the offset in the message's map.
        let ranges = Parser.messageRanges(inCarried: data)
        #expect(ranges.count == 2)
        let own = try Parser().sourceMap(of: data[ranges[1]])
        let ownControlID = try #require(own.range(of: WireLocation(segmentID: "MSH", segmentIndex: 1, fieldIndex: 10)))
        #expect(ranges[1].lowerBound + ownControlID.lowerBound == controlID.lowerBound)
    }
}
