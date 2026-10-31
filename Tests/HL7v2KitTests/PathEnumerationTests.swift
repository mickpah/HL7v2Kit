// PathEnumerationTests.swift
// P00 S2-2: populatedPaths() lists every non-empty leaf in document order with a fully
// indexed path, so the same location has the same key in every message.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Populated-path enumeration")
struct PathEnumerationTests {
    static let wire = "MSH|^~\\&|APP|FAC|||20260101||ADT^A01|C1|P|2.5.1\r"
        + "PID|1||A1~B2^^^AU&1.2&ISO||DOE^JO\r"
        + "NTE|1\r"
        + "NTE|2||\"\"\r"

    /// Counted by hand: MSH 10 (MSH-5, 6 and 8 empty), PID 8, NTE 1 and 2. The HL7 null
    /// `""` is a value and is listed.
    static let expected = [
        "MSH[1]-1~1.1.1=|",
        "MSH[1]-2~1.1.1=^~\\&",
        "MSH[1]-3~1.1.1=APP",
        "MSH[1]-4~1.1.1=FAC",
        "MSH[1]-7~1.1.1=20260101",
        "MSH[1]-9~1.1.1=ADT",
        "MSH[1]-9~1.2.1=A01",
        "MSH[1]-10~1.1.1=C1",
        "MSH[1]-11~1.1.1=P",
        "MSH[1]-12~1.1.1=2.5.1",
        "PID[1]-1~1.1.1=1",
        "PID[1]-3~1.1.1=A1",
        "PID[1]-3~2.1.1=B2",
        "PID[1]-3~2.4.1=AU",
        "PID[1]-3~2.4.2=1.2",
        "PID[1]-3~2.4.3=ISO",
        "PID[1]-5~1.1.1=DOE",
        "PID[1]-5~1.2.1=JO",
        "NTE[1]-1~1.1.1=1",
        "NTE[2]-1~1.1.1=2",
        "NTE[2]-3~1.1.1=\"\"",
    ]

    @Test("A hand-counted message lists every populated leaf in document order")
    func handCounted() throws {
        let entries = try Parser().parse(Self.wire).populatedPaths()
        #expect(entries.map { "\($0.path)=\($0.value)" } == Self.expected)
    }

    @Test("Over the corpus every entry reads back, keys are unique and parse back, and two calls agree")
    func corpus() throws {
        let urls = try FixtureCorpus.validFixtureURLs()
        try #require(!urls.isEmpty)
        for url in urls {
            let name = url.lastPathComponent
            let message = try Parser().parse(Data(contentsOf: url))
            let entries = message.populatedPaths()
            #expect(!entries.isEmpty, "\(name)")
            for entry in entries {
                if message[entry.path] != entry.value {
                    Issue.record("\(name): \(entry.path) reads \(message[entry.path] ?? "nil"), listed \(entry.value)")
                }
                if (try? Path(entry.path.description)) != entry.path {
                    Issue.record("\(name): \(entry.path) does not parse back")
                }
            }
            #expect(Set(entries.map(\.path)).count == entries.count, "\(name): duplicate paths")
            #expect(message.populatedPaths() == entries, "\(name)")
        }
    }
}
