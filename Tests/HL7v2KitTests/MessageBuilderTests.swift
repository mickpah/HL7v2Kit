// MessageBuilderTests.swift
// Pin the appendSegment contract: callers pass 1-indexed fields; the builder
// prepends the index-0 placeholder. Lands per NEXT_STEPS Task R1.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("MessageBuilder")
struct MessageBuilderTests {

    @Test("appendSegment prepends the index-0 placeholder")
    func appendSegmentPrependsPlaceholder() throws {
        var b = MessageBuilder(version: .v2_5_1)
        _ = b.msh(messageType: (code: "ADT", triggerEvent: "A01"), messageControlID: "X")
        b.appendSegment(id: "ZAB", fields: [.scalar("v1"), .scalar("v2")])
        let msg = try b.build()
        let zab = try #require(msg.segments.last)
        #expect(zab.segmentID == "ZAB")
        #expect(zab.fields.count == 3)             // [placeholder, "v1", "v2"]
        #expect(zab.fields[1].stringValue == "v1")
        #expect(zab.fields[2].stringValue == "v2")
    }

    @Test("appendSegment treats `fields` as 1-indexed; the caller does not pre-include the placeholder")
    func appendSegmentExpectsOneIndexedFields() throws {
        var b = MessageBuilder(version: .v2_5_1)
        _ = b.msh(messageType: (code: "ADT", triggerEvent: "A01"), messageControlID: "X")
        b.appendSegment(id: "ZAB", fields: [.scalar("v1")])
        let msg = try b.build()
        let zab = try #require(msg.segments.last)
        #expect(zab.fields.count == 2)             // [placeholder, "v1"] — no double-prepend
        #expect(zab.fields[1].stringValue == "v1")
    }

    @Test("appendSegment with an empty fields array still emits the placeholder")
    func appendSegmentEmpty() throws {
        var b = MessageBuilder(version: .v2_5_1)
        _ = b.msh(messageType: (code: "ADT", triggerEvent: "A01"), messageControlID: "X")
        b.appendSegment(id: "ZAB", fields: [])
        let msg = try b.build()
        let zab = try #require(msg.segments.last)
        #expect(zab.fields.count == 1)             // just the placeholder
    }
}
