// V271GrammarTests+Conditions.swift
// P10-5a: v2.7.1 conditions for the orders, results, pharmacy and specimen segments
// (CH04, CH04A, CH07, CH13, and CH08's OM7 and PRC). Each position was read against its
// v2.7.1 field definition; the quotes and the bare positions are in
// docs/design/conditional-completeness-audit.md, "v2.7.1 (P10-5a)". A stored rule equals
// v2.8.2's or v2.6's only where the v2.7.1 sentence is that version's sentence.

import Testing
@testable import HL7v2Kit

extension V271GrammarTests {

    /// The segments P10-5a audited.
    static let p105aSegments: Set<String> = [
        "BLG", "BPO", "BPX", "BTX", "IPC", "OBR", "ODS", "ODT", "ORC", "RQ1", "RQD", "TQ1", "TQ2",
        "RXA", "RXC", "RXD", "RXE", "RXG", "RXO", "RXR",
        "CSP", "CSR", "CSS", "CTI", "FAC", "OBX", "PAC", "PCR", "PDC", "PEO", "PES", "PRT", "PSH",
        "SHP", "SPM",
        "CNS", "ECD", "ECR", "EQP", "EQU", "INV", "ISD", "NDS", "SAC", "SID", "TCC", "TCD",
        "OM7", "PRC",
    ]

    /// The governing v2.7.1 sentence is v2.8.2's, so the stored rule is v2.8.2's. OBR-7 and
    /// OBR-25 read "a report message"; v2.7.1 CH07 section 7.2.3 (p. 14) withdraws QRY/ORF
    /// "as of v2.7", so the report set is v2.8.2's (ORU, OUL, OPU), not v2.6's. ORC-25,
    /// OBX-12 and RXR-6 are printed O and carry only the prohibition their definition states.
    static let p105aFromV282 = [
        "BPX-5", "BPX-6", "BPX-8", "BPX-9", "BPX-10",
        "BTX-2", "BTX-3", "BTX-4", "BTX-5", "BTX-6", "BTX-7",
        "OBR-7", "OBR-22", "OBR-25", "ORC-25", "ORC-26",
        "RQ1-2", "RQ1-3", "RQ1-4", "RQ1-5", "RQD-2", "RQD-3", "RQD-4",
        "TQ1-12", "TQ2-3", "TQ2-4", "TQ2-5", "TQ2-6", "TQ2-7", "TQ2-10",
        "RXO-1", "RXO-2", "RXO-4", "RXR-6",
        "CSR-8", "CSR-9", "CSR-10", "CSR-14", "CSR-15", "CSR-16", "CTI-2",
        "OBX-2", "OBX-5", "OBX-12", "PAC-2", "PRT-6", "PRT-7", "PRT-14", "SPM-13",
        "OM7-16", "OM7-18", "PRC-5",
    ]

    /// The placer and filler number rules. v2.7.1 CH04 sections 4.5.1.2, 4.5.1.3, 4.5.3.2
    /// and 4.5.3.3 print the v2.6 sentences ("If the placer order number is not present in
    /// the ORC, it must be present in the associated OBR and vice versa"), not v2.8.2's
    /// "either a placer or a filler id with an exception for ... 'Send Number'". The
    /// `messageCode not in (OUL, OPU, OPL)` gates are kept (P10 ruling C5).
    static let p105aFromV26 = ["OBR-2", "OBR-3", "ORC-2", "ORC-3"]

    /// v2.7.1's own readings. PRT: CH07 sections 7.3.4.5 and 7.3.4.8 to 7.3.4.10 name four
    /// fields ("Participation Person, Participation Organization, Participation Location, or
    /// Participation Device"); v2.7.1 PRT has no PRT-22 Device Type. EQU-3: CH13 section
    /// 13.4.1.3 (p. 20): "The Equipment State is required in the ESU message and is optional
    /// otherwise."
    static let p105aOwn: [String: String] = [
        "PRT-5": "PRT-8 empty AND PRT-9 empty AND PRT-10 empty",
        "PRT-8": "PRT-5 empty AND PRT-9 empty AND PRT-10 empty",
        "PRT-9": "PRT-5 empty AND PRT-8 empty AND PRT-10 empty",
        "PRT-10": "PRT-5 empty AND PRT-8 empty AND PRT-9 empty",
        "EQU-3": "messageCode = ESU",
    ]

    private static func grammarField(_ table: [String: SegmentGrammar], _ position: String) throws -> FieldGrammar {
        let parts = position.split(separator: "-")
        let index = try #require(Int(parts[1]), "\(position)")
        return try #require(table[String(parts[0])]?.field(index), "\(position)")
    }

    @Test("Every v2.7.1 condition, prohibition and additional prohibition parses")
    func v271ConditionsParse() {
        var failures: [String] = []
        for (id, grammar) in SegmentGrammarTable.v2_7_1 {
            for field in grammar.fields {
                let rules = [field.condition, field.prohibitedWhen].compactMap { $0 }
                    + field.additionalProhibitions.map(\.condition)
                for rule in rules {
                    failures += Validator.conditionParseErrors(rule).map { "\(id)-\(field.index) '\(rule)': \($0)" }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test("P10-5a: the conditioned set, each rule equal to the version whose text v2.7.1 prints")
    func p105aConditions() throws {
        let v271 = SegmentGrammarTable.v2_7_1
        var conditioned = Set<String>()
        for (id, grammar) in v271 where Self.p105aSegments.contains(id) {
            for field in grammar.fields where field.condition != nil || field.prohibitedWhen != nil {
                conditioned.insert("\(id)-\(field.index)")
            }
        }
        let expected = Set(Self.p105aFromV282 + Self.p105aFromV26 + Array(Self.p105aOwn.keys))
        #expect(expected.count == 61)
        #expect(conditioned == expected, "got \(conditioned.sorted())")

        for (positions, sibling) in [(Self.p105aFromV282, SegmentGrammarTable.v2_8_2),
                                     (Self.p105aFromV26, SegmentGrammarTable.v2_6)] {
            for position in positions {
                let mine = try Self.grammarField(v271, position)
                let theirs = try Self.grammarField(sibling, position)
                #expect(mine.condition == theirs.condition, "\(position)")
                #expect(mine.prohibitedWhen == theirs.prohibitedWhen, "\(position)")
                #expect(mine.prohibitedSeverity == theirs.prohibitedSeverity, "\(position)")
                #expect(mine.additionalProhibitions == theirs.additionalProhibitions, "\(position)")
            }
        }
        for (position, condition) in Self.p105aOwn {
            let field = try Self.grammarField(v271, position)
            #expect(field.condition == condition, "\(position)")
            #expect(field.prohibitedWhen == nil, "\(position)")
        }
    }

    @Test("Where the v2.7.1 text differs from v2.8.2's, the v2.7.1 reading is stored")
    func p105aDifferences() throws {
        let v271 = SegmentGrammarTable.v2_7_1, v282 = SegmentGrammarTable.v2_8_2
        // No Send Number exception in v2.7.1 (CH04 section 4.5.3.2, p. 55-56).
        let obr2 = try #require(try Self.grammarField(v271, "OBR-2").condition)
        #expect(!obr2.contains("ORC-1 != SN"))
        #expect(try Self.grammarField(v282, "OBR-2").condition?.contains("ORC-1 != SN") == true)
        // No PRT-22 leg (CH07 section 7.3.4.5, p. 71).
        #expect(try Self.grammarField(v282, "PRT-5").condition?.contains("PRT-22") == true)
        #expect(v271["PRT"]?.fields.count == 15)
        // EQU-3 is bare on v2.8.2 although the sentence is the same (see the audit).
        #expect(try Self.grammarField(v282, "EQU-3").condition == nil)
        // OBR-7 and OBR-25: the v2.6 report set lists ORF; v2.7.1 withdraws it.
        #expect(try Self.grammarField(SegmentGrammarTable.v2_6, "OBR-7").condition == "messageCode in (ORU, ORF, OUL, OPU)")
        #expect(try Self.grammarField(v271, "OBR-7").condition == "messageCode in (ORU, OUL, OPU)")
    }

    @Test("Table versus definition: CSR-8 modelled C (P4-30); RXA-4 stays R (G8)")
    func p105aTableVersusDefinition() throws {
        // CH07 section 7.7.1.8 (p. 96): the table (p. 93) prints R; "This field is required
        // for the patient registration trigger event (C01)".
        let csr8 = try Self.grammarField(SegmentGrammarTable.v2_7_1, "CSR-8")
        #expect(csr8.optionality == .conditional)
        #expect(csr8.condition == "triggerEvent = C01")
        // CH04A section 4A.4.7.4 (p. 89): "If null, the date/time of RXA-3 ... is assumed":
        // the HL7 null "" satisfies R, so RXA-4 keeps its printed R.
        let rxa4 = try Self.grammarField(SegmentGrammarTable.v2_7_1, "RXA-4")
        #expect(rxa4.optionality == .required)
        #expect(rxa4.condition == nil)
    }
}
