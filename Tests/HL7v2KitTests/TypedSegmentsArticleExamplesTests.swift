// TypedSegmentsArticleExamplesTests.swift
// The "Composite components and later-version accessors" examples in
// TypedSegments.md (ADR-020), compiled and run so the article cannot drift.

import Testing
import Foundation
@testable import HL7v2Kit

@Suite("TypedSegments article examples (ADR-020)")
struct TypedSegmentsArticleExamplesTests {

    @Test("Composite component accessors, component(_:as:) and viewed(as:)")
    func compositeExamples() throws {
        let wire = TestWires.adt("PID|1||111^^^HOSP&1.2.3&ISO^MR^^20200101||Smith^John")
        let pid = try hydrated(PID.self, from: wire)
        let cx = try #require(pid.patientIdentifierList)
        #expect(cx.effectiveDate == "20200101")
        #expect(cx.component(4, as: HD.self)?.universalID == "1.2.3")
        // Absent component: nil. Present but empty component: an empty view.
        #expect(cx.component(9, as: HD.self) == nil)
        let emptyFive = try #require(try hydrated(PID.self, from: TestWires.adt("PID|1||111^^^HOSP^^FAC")).patientIdentifierList)
        #expect(emptyFive.component(5, as: HD.self) != nil)
        #expect(emptyFive.component(5, as: HD.self)?.namespaceID == "")
        let obx = try hydrated(OBX.self, from: TestWires.adt("OBX|1|ST|1234^Test^L||x"))
        #expect(obx.observationIdentifier?.viewed(as: CWE.self).identifier == "1234")
    }

    @Test("All accessors and later-version fields")
    func versionExamples() throws {
        let wire = TestWires.adt("PID|1||111^^^HOSP^MR~222^^^GOV^MC")
        let pid = try hydrated(PID.self, from: wire)
        #expect(pid.patientIdentifierListAll.map(\.id) == ["111", "222"])
        let obx = try hydrated(OBX.self, from: TestWires.adt("OBX|1|ST|1234^Test^L||x"))
        #expect(obx.observationType == nil)        // OBX-29, v2.8.2 only: absent here
    }
}
