// WireTextTests.swift
// Message.wireText(at:): the text of a value as the serialiser writes it (P01 R13).

import Foundation
import Testing
@testable import HL7v2Kit

@Suite("Wire text of a value")
struct WireTextTests {
    static let msh = "MSH|^~\\&|APP|FAC|||||ORU^R01|MSG1|P|2.5.1\r"

    @Test("A composite comes back as written, escapes kept; the decoded read is unchanged")
    func compositeAsWritten() throws {
        let message = try Parser().parse(Self.msh + "OBX|1|ST|X||A\\S\\B^C~D&E^F\r")
        #expect(try message.wireText(at: Path("OBX-5")) == "A\\S\\B^C~D&E^F")      // the whole field
        #expect(try message.wireText(at: Path("OBX-5~1")) == "A\\S\\B^C")
        #expect(try message.wireText(at: Path("OBX-5~2")) == "D&E^F")
        #expect(try message.wireText(at: Path("OBX-5.1")) == "A\\S\\B")            // first repetition, as the subscript reads
        #expect(try message.wireText(at: Path("OBX-5~2.1")) == "D&E")
        #expect(try message.wireText(at: Path("OBX-5~2.1.2")) == "E")
        #expect(message["OBX-5.1"] == "A^B")                                        // decoded, not re-parseable
    }

    @Test("MSH-1 and MSH-2 are their literal characters")
    func delimiterFields() throws {
        let message = try Parser().parse(Self.msh)
        #expect(try message.wireText(at: Path("MSH-1")) == "|")
        #expect(try message.wireText(at: Path("MSH-2")) == "^~\\&")
        #expect(try message.wireText(at: Path("MSH-2.1")) == "^~\\&")
        #expect(try message.wireText(at: Path("MSH-2.2")) == nil)
        #expect(try message.wireText(at: Path("MSH-9")) == "ORU^R01")
    }

    @Test("A value set in code is encoded")
    func valueSetInCode() throws {
        var message = try Parser().parse(Self.msh + "NTE|1||x\r")
        try message.set("a|b^c", at: Path("NTE-3"))
        #expect(try message.wireText(at: Path("NTE-3")) == "a\\F\\b\\S\\c")
        #expect(message["NTE-3"] == "a|b^c")
    }

    @Test("Nothing for a wildcard, a segment alone, or a place the message does not have")
    func nothingThere() throws {
        let message = try Parser().parse(Self.msh + "OBX|1|ST|X||A^B\r")
        for text in ["OBX[*]-5", "OBX-5[*]", "OBX", "OBX[2]-5", "OBX-9", "OBX-5~2", "OBX-5.3", "OBX-5.1.2", "ZZZ-1"] {
            #expect(try message.wireText(at: Path(text)) == nil, "\(text)")
        }
        // A subcomponent without a component names no place.
        #expect(message.wireText(at: Path(segmentID: "OBX", field: 5, subcomponent: 1)) == nil)
    }

    @Test("Agreement: every value's wire text is its bytes in the serialised message")
    func agreesWithTheSourceMap() throws {
        for url in try FixtureCorpus.validFixtureURLs() {
            let name = url.lastPathComponent
            let message = try Parser().parse(Data(contentsOf: url))
            let written = message.serialize()
            let map = try Parser().sourceMap(of: written)
            var checked = 0
            func check(_ id: String, _ n: Int, _ indices: [Int]) {
                let place = SourceMapTests.place(id, n, indices)
                guard let path = place.path, let range = map.range(of: place),
                      let expected = SourceMapTests.text(written, range, message.characterEncoding) else {
                    Issue.record("\(name) \(place): no path, range or text")
                    return
                }
                checked += 1
                if !SourceMapTests.same(message.wireText(at: path), expected) {
                    Issue.record("\(name) \(path): wireText \(String(describing: message.wireText(at: path))), written \(expected)")
                }
            }
            var occurrence: [String: Int] = [:]
            for segment in message.segments {
                let id = segment.segmentID
                occurrence[id, default: 0] += 1
                let n = occurrence[id] ?? 1
                for (f, field) in segment.fields.enumerated() where f >= 1 {
                    check(id, n, [f])
                    for (r, repetition) in field.repetitions.enumerated() {
                        check(id, n, [f, r + 1])
                        for (c, component) in repetition.components.enumerated() {
                            check(id, n, [f, r + 1, c + 1])
                            for s in component.subcomponents.indices { check(id, n, [f, r + 1, c + 1, s + 1]) }
                        }
                    }
                }
            }
            #expect(checked > 0, "\(name)")
        }
    }
}
