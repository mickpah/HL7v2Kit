// CompositeAccessHelperTests.swift
// P9-2: the access helpers the generated accessors build on —
// sub-composite views, re-viewing a field as another composite, and
// per-repetition fields.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("Composite and segment access helpers (P9-2)")
struct CompositeAccessHelperTests {

    private let wire = TestWires.adt("PID|1||123^^^HOSP&1.2.36.1&ISO^MR~456^^^GOV^MC")

    @Test("component(_:as:) views a sub-composite's subcomponents as its components")
    func subComponentView() throws {
        let (message, pid) = try hydratedMessage(PID.self, from: wire)
        let cx = try #require(pid.patientIdentifierList)
        let hd = try #require(cx.component(4, as: HD.self))
        #expect(hd.namespaceID == "HOSP")
        #expect(hd.universalID == "1.2.36.1")
        #expect(hd.universalID == message["PID-3.4.2"])
        #expect(hd.universalIDType == message["PID-3.4.3"])
        #expect(cx.component(40, as: HD.self) == nil)
        #expect(cx.component(0, as: HD.self) == nil)
    }

    @Test("viewed(as:) re-views the same field as another composite")
    func viewedAs() throws {
        let pid = try hydrated(PID.self, from: wire)
        let cx = try #require(pid.patientIdentifierList)
        let asEI = cx.viewed(as: EI.self)
        #expect(asEI.field == cx.field)
        #expect(asEI.entityIdentifier == cx.id)
    }

    @Test("repetitions(_:) returns each repetition as its own field, in wire order")
    func repetitionsHelper() throws {
        let pid = try hydrated(PID.self, from: wire)
        let reps = pid.repetitions(3)
        #expect(reps.count == 2)
        #expect(reps.map { CX(field: $0).id } == ["123", "456"])
        #expect(pid.repetitions(39).isEmpty)
        #expect(pid.repetitions(0).isEmpty)
    }

    @Test("HL7 null, empty component and an escape read as the validator reads them")
    func nullEmptyEscape() throws {
        let pid = try hydrated(PID.self, from: TestWires.adt("PID|1||123^^^\"\"&1.2^MR~^^^&&"))
        let reps = pid.repetitions(3)
        #expect(reps.count == 2)
        let nullHD = try #require(CX(field: reps[0]).component(4, as: HD.self))
        #expect(nullHD.namespaceID == "\"\"")
        #expect(nullHD.universalID == "1.2")
        let emptyHD = try #require(CX(field: reps[1]).component(4, as: HD.self))
        #expect(emptyHD.namespaceID == "")
        #expect(emptyHD.universalID == "")
        #expect(CX(field: reps[1]).component(2, as: HD.self)?.namespaceID == "")

        let esc = try hydrated(PID.self, from: TestWires.adt("PID|1||A\\S\\B^^^NS\\S\\X&1.2"))
        let cx = try #require(esc.patientIdentifierList)
        #expect(cx.id == "A^B")
        #expect(cx.component(4, as: HD.self)?.namespaceID == "NS^X")
    }
}
