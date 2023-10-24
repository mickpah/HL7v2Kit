// CrossSegmentDSLTests.swift
// v0.7-S2 pins for ADR-008's three new predicate productions. Each
// production has a positive case (fires correctly), a negative case
// (doesn't fire when not satisfied), and a fail-safe case (returns
// false when the referent is unresolvable rather than crashing or
// triggering a spurious error).
//
// The tests reach `Validator.conditionTriggers` via `@testable import`
// — the parser entry point is internal so the productions can be
// exercised without injecting synthetic grammar entries. (The actual
// schema conditions land in S3.)

import Testing
@testable import HL7v2Kit

@Suite("Cross-segment / message-context DSL (v0.7-S2)")
struct CrossSegmentDSLTests {

    // ORU report message with one fully-populated ORC/OBR group:
    //   ORC-1 = RE, ORC-2 = ORD001
    //   OBR-2 = ORD001, OBR-25 empty
    private let oruOneGroupBothPopulated = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01^ORU_R01|MSG0001|P|2.5.1\r\
    PID|1||123^^^HOSP^MR||Doe^Jane||19800101|F\r\
    ORC|RE|ORD001||GROUP001|CM\r\
    OBR|1|ORD001|FIL001|GLUC^Glucose\r\
    OBX|1|NM|GLUC^Glucose||5.5|mmol/L||N|||F\r
    """

    // Same shape but with ORC-2 (placer order) empty — the XOR rule's
    // "ORC side missing, OBR side carries it" wire.
    private let oruORCPlacerEmpty = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01^ORU_R01|MSG0002|P|2.5.1\r\
    PID|1||123^^^HOSP^MR||Doe^Jane||19800101|F\r\
    ORC|RE|||GROUP001|CM\r\
    OBR|1|ORD001|FIL001|GLUC^Glucose\r
    """

    // Both ORC-2 AND OBR-2 empty — the XOR rule should fire on either
    // side when expressed as `<peer>-2 empty`.
    private let oruBothPlacersEmpty = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01^ORU_R01|MSG0003|P|2.5.1\r\
    PID|1||123^^^HOSP^MR||Doe^Jane||19800101|F\r\
    ORC|RE|||GROUP001|CM\r\
    OBR|1||FIL001|GLUC^Glucose\r
    """

    // ADT^A01 — not a report message; OBR-25 conditional wouldn't fire.
    private let adtA01 = """
    MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20260619120000||ADT^A01|MSG0004|P|2.5.1\r\
    PID|1||123^^^HOSP^MR||Smith^John||19800101|M\r
    """

    // Parent/child ORC pair: first ORC carries ORC-1 = PA, second
    // carries ORC-1 = CH. The ORC-8 rule on the CH segment should
    // resolve `previousSegment(ORC).ORC-1 = PA` to true.
    private let parentChildORC = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01^ORU_R01|MSG0005|P|2.5.1\r\
    PID|1||123^^^HOSP^MR||Doe^Jane||19800101|F\r\
    ORC|PA|ORD001||GROUP001|CM\r\
    OBR|1|ORD001|FIL001|GLUC^Glucose\r\
    ORC|CH|ORD002||GROUP001|CM\r\
    OBR|2|ORD002|FIL002|HBA1C^HbA1c\r
    """

    // No parent ORC — the child-only wire. `previousSegment(ORC).ORC-1`
    // resolves but returns the only ORC (which carries CH, not PA).
    private let childOnlyORC = """
    MSH|^~\\&|HIS|FAC|LAB|FAC|20260619120000||ORU^R01^ORU_R01|MSG0006|P|2.5.1\r\
    PID|1||123^^^HOSP^MR||Doe^Jane||19800101|F\r\
    ORC|CH|ORD002||GROUP001|CM\r\
    OBR|2|ORD002|FIL002|HBA1C^HbA1c\r
    """

    // Helper — find the 0-based index of the first segment of `id`.
    private func index(of id: String, in message: Message) throws -> Int {
        try #require(message.segments.firstIndex { $0.segmentID == id })
    }

    // Helper — evaluate a condition string against the first segment of
    // `currentSegmentID` in the message. Returns the parser's verdict.
    private func evaluate(
        _ condition: String,
        as currentSegmentID: String,
        in message: Message
    ) throws -> Bool {
        let segmentIndex = try index(of: currentSegmentID, in: message)
        return Validator().conditionTriggers(
            condition,
            in: message.segments[segmentIndex],
            segmentIndex: segmentIndex,
            message: message,
            currentSegmentID: currentSegmentID
        )
    }

    // MARK: - Production 1: cross-segment field refs

    @Test("Cross-segment ref: ORC sees OBR-2 populated in its group")
    func crossSegmentFieldRefPositive() throws {
        let message = try Parser().parse(oruOneGroupBothPopulated)
        #expect(try evaluate("OBR-2 populated", as: "ORC", in: message))
    }

    @Test("Cross-segment ref: ORC sees OBR-2 empty when placer carried only on ORC")
    func crossSegmentFieldRefNegative() throws {
        // OBR-2 = ORD001 here, ORC-2 empty. So `OBR-2 empty` is false.
        let message = try Parser().parse(oruORCPlacerEmpty)
        #expect(try evaluate("OBR-2 empty", as: "ORC", in: message) == false)
    }

    @Test("Cross-segment ref: OBR sees ORC-2 empty when placer absent")
    func crossSegmentFieldRefSymmetric() throws {
        let message = try Parser().parse(oruORCPlacerEmpty)
        #expect(try evaluate("ORC-2 empty", as: "OBR", in: message))
    }

    @Test("Cross-segment ref: both placers empty fires the XOR on both sides")
    func crossSegmentXORBothEmpty() throws {
        let message = try Parser().parse(oruBothPlacersEmpty)
        #expect(try evaluate("OBR-2 empty", as: "ORC", in: message))
        #expect(try evaluate("ORC-2 empty", as: "OBR", in: message))
    }

    @Test("Cross-segment ref: missing peer segment fails safe to false")
    func crossSegmentFieldRefMissingPeer() throws {
        // ADT^A01 has no ORC or OBR. From PID, asking about ORC-2
        // should resolve to no peer → atom evaluates false (not crash).
        let message = try Parser().parse(adtA01)
        #expect(try evaluate("ORC-2 populated", as: "PID", in: message) == false)
        #expect(try evaluate("ORC-2 empty", as: "PID", in: message) == false)
    }

    // MARK: - Production 2: message-context atoms

    @Test("messageCode = ORU on report message")
    func messageCodePositive() throws {
        let message = try Parser().parse(oruOneGroupBothPopulated)
        #expect(try evaluate("messageCode = ORU", as: "OBR", in: message))
    }

    @Test("messageCode = ORU on ADT message is false")
    func messageCodeNegative() throws {
        let message = try Parser().parse(adtA01)
        #expect(try evaluate("messageCode = ORU", as: "PID", in: message) == false)
    }

    @Test("triggerEvent = R01 on ORU^R01 message")
    func triggerEventPositive() throws {
        let message = try Parser().parse(oruOneGroupBothPopulated)
        #expect(try evaluate("triggerEvent = R01", as: "OBR", in: message))
    }

    @Test("messageStructure = ORU_R01 reads MSH-9.3 component")
    func messageStructurePositive() throws {
        let message = try Parser().parse(oruOneGroupBothPopulated)
        #expect(try evaluate("messageStructure = ORU_R01", as: "OBR", in: message))
    }

    @Test("messageStructure populated fails safe to false on legacy two-component MSH-9")
    func messageStructureFailSafe() throws {
        // adtA01's MSH-9 is `ADT^A01` — no third component. The atom
        // resolves to empty; `populated` is false.
        let message = try Parser().parse(adtA01)
        #expect(try evaluate("messageStructure populated", as: "PID", in: message) == false)
    }

    // MARK: - Production 3: position atoms

    @Test("previousSegment(ORC).ORC-1 = PA on child ORC after parent ORC")
    func previousSegmentPositive() throws {
        // The second ORC carries CH; the previous ORC carries PA.
        // Evaluating from the second ORC's perspective.
        let message = try Parser().parse(parentChildORC)
        let secondORCIndex = try #require(
            message.segments.enumerated()
                .filter { _, s in s.segmentID == "ORC" }
                .map(\.offset).dropFirst().first
        )
        let triggered = Validator().conditionTriggers(
            "previousSegment(ORC).ORC-1 = PA",
            in: message.segments[secondORCIndex],
            segmentIndex: secondORCIndex,
            message: message,
            currentSegmentID: "ORC"
        )
        #expect(triggered)
    }

    @Test("previousSegment(ORC).ORC-1 = PA is false when no parent ORC precedes")
    func previousSegmentNoParent() throws {
        let message = try Parser().parse(childOnlyORC)
        #expect(try evaluate(
            "previousSegment(ORC).ORC-1 = PA",
            as: "ORC",
            in: message
        ) == false)
    }

    @Test("previousSegment(ORC).ORC-1 on PID (no ORC precedes) fails safe to false")
    func previousSegmentFailSafe() throws {
        let message = try Parser().parse(oruOneGroupBothPopulated)
        #expect(try evaluate(
            "previousSegment(ORC).ORC-1 = PA",
            as: "PID",
            in: message
        ) == false)
    }

    @Test("associatedSegment(OBR).OBR-2 populated from ORC")
    func associatedSegmentExplicitForm() throws {
        let message = try Parser().parse(oruOneGroupBothPopulated)
        #expect(try evaluate(
            "associatedSegment(OBR).OBR-2 populated",
            as: "ORC",
            in: message
        ))
    }

    // MARK: - Compound predicates mixing productions

    @Test("AND combinator: OBR-2 empty AND messageCode = ORU")
    func compoundCrossSegmentAndMessageContext() throws {
        let message = try Parser().parse(oruBothPlacersEmpty)
        #expect(try evaluate(
            "OBR-2 empty AND messageCode = ORU",
            as: "ORC",
            in: message
        ))
        // ORC-2 populated would make `OBR-2 empty` still true (OBR-2
        // is empty) — but flip the conjunct on a wire where the placer
        // is on ORC, OBR-2 carries it, so OBR-2 empty is false.
        let withPlacerOnOBR = try Parser().parse(oruORCPlacerEmpty)
        #expect(try evaluate(
            "OBR-2 empty AND messageCode = ORU",
            as: "ORC",
            in: withPlacerOnOBR
        ) == false)
    }

    // MARK: - Regression pins (v0.4-S4 same-segment DSL stays working)

    @Test("v0.4-S4 regression: same-segment ref still resolves directly")
    func sameSegmentRefRegression() throws {
        // PID-37 ("DeKalb") populated, PID-36 empty. From PID context,
        // `PID-37 populated` should be true.
        let wire = """
        MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01|MSG|P|2.5.1\r\
        PID|1||123^^^HOSP^MR||Smith^John^A||19800101|M|||||||||||||||||||||||||||||DeKalb\r
        """
        let message = try Parser().parse(wire)
        #expect(try evaluate("PID-37 populated", as: "PID", in: message))
    }
}
