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
        // EQU-3: v2.4, v2.5.1, v2.6 and v2.8.2 print the same CH13 13.4.1.3 sentence, so
        // P10-5b's intake gave them v2.7.1's rule (v2.3 and v2.3.1 have no EQU).
        for table in [SegmentGrammarTable.v2_4, SegmentGrammarTable.v2_5_1, SegmentGrammarTable.v2_6, v282] {
            #expect(try Self.grammarField(table, "EQU-3").condition == "messageCode = ESU")
        }
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

    // MARK: - P10-5b: every other chapter (CH03, CH05, CH06, CH08 to CH12, CH15, CH16)

    /// The segments P10-5b audited: every v2.7.1 segment with a printed C outside P10-5a's
    /// chapters, plus MFI and ROL for their table-versus-definition fields.
    static let p105bSegments: Set<String> = [
        "ADJ", "AIG", "AIL", "AIP", "AIS", "ARQ", "AUT", "CER", "DG1", "DMI", "GOL", "IAM", "IVC",
        "LRL", "MFA", "MFE", "MFI", "PD1", "PID", "PR1", "PRA", "PRB", "PSL", "PTH", "PV2", "PYE",
        "QAK", "QPD", "RCP", "REL", "RGS", "ROL", "SCH", "STF", "TXA",
    ]

    /// Every segment whose v2.7.1 fields may carry a condition; the rest carry none.
    static let conditionedSegments = p105aSegments.union(p105bSegments)

    /// The governing v2.7.1 sentence is v2.8.2's (word for word, or differing only in a
    /// cross-reference or an inline code table), so the stored rule is v2.8.2's. AIS-10,
    /// AIG-14, AIL-12 and AIP-12 take v2.8.2's filler set (SIU, SRR): CH10 section 10.5.3
    /// (p. 22) withdraws SQM/SQR "as of v2.7". MFI-6 and ROL-4 are printed R (P4-30).
    static let p105bFromV282 = [
        "AIG-3", "AIG-8", "AIG-9", "AIG-10", "AIG-13", "AIG-14",
        "AIL-3", "AIL-4", "AIL-6", "AIL-7", "AIL-8", "AIL-11", "AIL-12",
        "AIP-3", "AIP-4", "AIP-6", "AIP-7", "AIP-8", "AIP-11", "AIP-12",
        "AIS-4", "AIS-6", "AIS-9", "AIS-10", "ARQ-25", "SCH-1", "SCH-2", "SCH-27",
        "DG1-20", "DG1-21", "PR1-19", "PR1-20", "PD1-15", "PV2-1", "PV2-45", "PV2-47",
        "LRL-5", "LRL-6", "MFA-2", "MFE-2", "MFI-6", "PRA-1", "PRA-12", "STF-1", "ROL-4",
        "PYE-3", "PYE-4", "PYE-5", "PYE-6", "TXA-3", "TXA-5", "TXA-7", "TXA-13",
    ]

    /// PID-35 and PID-36 print v2.6's "Conditionality Rule" sentences (CH03 section 3.4.2.35
    /// and 3.4.2.36, p. 73); v2.8.2 prints PID-35 O and withdraws PID-36.
    static let p105bFromV26 = ["PID-35", "PID-36"]

    /// v2.7.1's own readings, where v2.6 and v2.8.2 print the same sentence but leave the
    /// field bare. RCP-4: CH05 section 5.5.6.4 (p. 47), "This field is only valued when
    /// RCP-1-Query priority contains the value D (Deferred)". ROL-1: CH15 section 15.4.7.1
    /// (p. 33), "This field is required when used in Patient Care and Personnel Management
    /// messages" (the Chapter 12 and Chapter 15 message types, RSP^K25 included).
    static let p105bOwnConditions: [String: String] = [
        "ROL-1": "messageCode in (PGL, PPG, PPP, PPR, PPT, PPV, PRR, PTR, PMU) OR messageCode = RSP AND triggerEvent = K25",
    ]
    static let p105bOwnProhibitions: [String: String] = ["RCP-4": "RCP-1 != D"]

    @Test("P10-5b: the conditioned set, each rule equal to the version whose text v2.7.1 prints")
    func p105bConditions() throws {
        let v271 = SegmentGrammarTable.v2_7_1
        var conditioned = Set<String>()
        for (id, grammar) in v271 where Self.p105bSegments.contains(id) {
            for field in grammar.fields where field.condition != nil || field.prohibitedWhen != nil {
                conditioned.insert("\(id)-\(field.index)")
            }
        }
        let expected = Set(Self.p105bFromV282 + Self.p105bFromV26
                           + Array(Self.p105bOwnConditions.keys) + Array(Self.p105bOwnProhibitions.keys))
        #expect(expected.count == 57)
        #expect(conditioned == expected, "got \(conditioned.sorted())")
        #expect(Self.p105aSegments.isDisjoint(with: Self.p105bSegments))

        for (positions, sibling) in [(Self.p105bFromV282, SegmentGrammarTable.v2_8_2),
                                     (Self.p105bFromV26, SegmentGrammarTable.v2_6)] {
            for position in positions {
                let mine = try Self.grammarField(v271, position)
                let theirs = try Self.grammarField(sibling, position)
                #expect(mine.condition == theirs.condition, "\(position)")
                #expect(mine.prohibitedWhen == theirs.prohibitedWhen, "\(position)")
                #expect(mine.prohibitedSeverity == theirs.prohibitedSeverity, "\(position)")
                #expect(mine.additionalProhibitions == theirs.additionalProhibitions, "\(position)")
            }
        }
        for (position, condition) in Self.p105bOwnConditions {
            let field = try Self.grammarField(v271, position)
            #expect(field.condition == condition, "\(position)")
            #expect(field.prohibitedWhen == nil, "\(position)")
        }
        for (position, prohibition) in Self.p105bOwnProhibitions {
            let field = try Self.grammarField(v271, position)
            #expect(field.condition == nil, "\(position)")
            #expect(field.prohibitedWhen == prohibition, "\(position)")
            #expect(field.prohibitedSeverity == .warning, "\(position)")
        }
    }

    @Test("P10-5b: where the v2.7.1 reading differs from v2.8.2's or v2.6's")
    func p105bDifferences() throws {
        let v26 = SegmentGrammarTable.v2_6, v271 = SegmentGrammarTable.v2_7_1, v282 = SegmentGrammarTable.v2_8_2
        // Filler status: v2.6 still defines SQR^S25; v2.7.1 CH10 section 10.5.3 withdraws it.
        #expect(try Self.grammarField(v26, "AIS-10").condition == "messageCode in (SIU, SRR, SQR)")
        #expect(try Self.grammarField(v271, "AIS-10").condition == "messageCode in (SIU, SRR)")
        // PID-35 and PID-36: v2.7.1 prints C with v2.6's rules; v2.8.2 prints O and B.
        #expect(try Self.grammarField(v282, "PID-35").optionality == .optional)
        #expect(try Self.grammarField(v282, "PID-36").condition == nil)
        #expect(try Self.grammarField(v271, "PID-36").optionality == .conditional)
        // RCP-4: v2.4 CH05 5.5.5.4 (p. 52), v2.5.1 5.5.6.4 (p. 49), v2.6 5.5.6.4 (p. 41) and
        // v2.8.2 5.5.6.4 (p. 46) print v2.7.1's sentence, "only valued when RCP-1-Query
        // priority contains the value D"; P10-7's intake gave them its prohibition. v2.3 and
        // v2.3.1 define no RCP.
        let v24 = SegmentGrammarTable.v2_4, v251 = SegmentGrammarTable.v2_5_1
        for table in [v24, v251, v26, v271, v282] {
            let rcp4 = try Self.grammarField(table, "RCP-4")
            #expect(rcp4.prohibitedWhen == "RCP-1 != D" && rcp4.prohibitedSeverity == .warning)
            #expect(rcp4.condition == nil)
        }
        // ROL-1: v2.5.1 CH15 15.4.7.1 (p. 27), v2.6 15.4.7.1 (p. 22) and v2.8.2 15.4.7.1
        // (p. 31) print v2.7.1's "required when used in Patient Care and Personnel Management
        // messages". v2.8.2 CH12 12.3.6 to 12.3.12 (p. 16) removes PRR, PPV, PTR and PPT "as
        // of v2.8", so its set drops them. v2.4 CH12 12.4.3.1 (p. 24) names Patient Care
        // messages only, a different sentence, and stays bare; v2.3 and v2.3.1 print R.
        let rolCare = "messageCode in (PGL, PPG, PPP, PPR, PPT, PPV, PRR, PTR, PMU) OR messageCode = RSP AND triggerEvent = K25"
        for table in [v251, v26, v271] {
            #expect(try Self.grammarField(table, "ROL-1").condition == rolCare)
        }
        #expect(try Self.grammarField(v282, "ROL-1").condition
                == "messageCode in (PGL, PPG, PPP, PPR, PMU) OR messageCode = RSP AND triggerEvent = K25")
        #expect(try Self.grammarField(v24, "ROL-1").condition == nil)
        #expect(try Self.grammarField(SegmentGrammarTable.v2_3_1, "ROL-1").optionality == .required)
        // TXA-11 and TXA-22: v2.8.2's "Condition" paragraphs on OBR-35 and OBR-32 are not in
        // the v2.7.1 print (CH09 sections 9.7.3.11 and 9.7.3.22); both stay bare here.
        #expect(try Self.grammarField(v271, "TXA-11").condition == nil)
        #expect(try Self.grammarField(v271, "TXA-22").condition == nil)
    }

    @Test("Table versus definition: MFI-6 and ROL-4 printed R, modelled C (P4-30)")
    func p105bTableVersusDefinition() throws {
        // CH08 section 8.5.1.6 (p. 8; table p. 7): "Required for MFN-Master File
        // Notification message". CH15 section 15.4.7.4 (p. 34; table p. 32): "If both STF
        // and ROL are present in the same message, populating this field is optional."
        let mfi6 = try Self.grammarField(SegmentGrammarTable.v2_7_1, "MFI-6")
        #expect(mfi6.optionality == .conditional)
        #expect(mfi6.condition == "messageCode = MFN")
        let rol4 = try Self.grammarField(SegmentGrammarTable.v2_7_1, "ROL-4")
        #expect(rol4.optionality == .conditional)
        #expect(rol4.condition == "STF absent")
    }
}
