import Testing
@testable import HL7v2Kit

/// M19 — a field's optionality is its OWN version's, never a later version's.
@Suite("Field optionality follows each version's attribute table")
struct OptionalityPerVersionTests {
    private func issues(_ wire: String) throws -> [ValidationIssue] {
        Validator().validate(try Parser().parse(wire)).issues
    }

    @Test("MSH-7 Date/Time of Message is O in v2.3 and v2.3.1, R from v2.4")
    func msh7() throws {
        for (version, required) in [("2.3", false), ("2.3.1", false), ("2.4", true), ("2.5.1", true)] {
            let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|||ADT^A01^ADT_A01|MSG00001|P|\(version)\rPID|1||123^^^AUTH^MR||DOE^JOHN\r"
            let missing = try issues(wire).contains { $0.code == .requiredFieldMissing && $0.location.pathDescription == "MSH[1]-7" }
            #expect(missing == required, "v\(version)")
        }
    }

    @Test("PID-2 is an ordinary optional field in v2.3: no deprecation warning until a version deprecates it")
    func pid2() throws {
        func warned(_ version: String) throws -> Bool {
            let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101||ADT^A01^ADT_A01|MSG00001|P|\(version)\rPID|1|EXT99|123^^^AUTH^MR||DOE^JOHN\r"
            return try issues(wire).contains { $0.code == .fieldNotSupported && $0.location.pathDescription == "PID[1]-2" }
        }
        #expect(try !warned("2.3"), "v2.3 prints PID-2 as O")
        #expect(try warned("2.5.1"), "v2.5.1 prints PID-2 as B")
        #expect(SegmentGrammarTable.v2_3["PID"]?.field(2)?.name == "Patient ID", "and carries no '(deprecated)' suffix there")
    }

    @Test("v2.6 prints DG1-3 Diagnosis Code as R and MSA-5 as W")
    func v26() throws {
        #expect(SegmentGrammarTable.v2_6["DG1"]?.field(3)?.optionality == .required)
        #expect(SegmentGrammarTable.v2_5_1["DG1"]?.field(3)?.optionality == .optional)
        #expect(SegmentGrammarTable.v2_6["MSA"]?.field(5)?.optionality == .withdrawn)
        #expect(SegmentGrammarTable.v2_6["OBR"]?.field(33)?.optionality == .backwardCompat)
    }

    @Test("No field name is cut at its left edge: 110 pharmacy names shipped that way before M20")
    func noTruncatedNames() {
        for (version, table) in [("2.3", SegmentGrammarTable.v2_3), ("2.3.1", SegmentGrammarTable.v2_3_1), ("2.4", SegmentGrammarTable.v2_4),
                                 ("2.5.1", SegmentGrammarTable.v2_5_1), ("2.6", SegmentGrammarTable.v2_6), ("2.8.2", SegmentGrammarTable.v2_8_2)] {
            for grammar in table.values {
                for field in grammar.fields {
                    #expect(field.name.first?.isUppercase == true || field.name.first?.isNumber == true,
                            "v\(version) \(grammar.segmentID)-\(field.index): \(field.name)")
                }
            }
        }
        #expect(SegmentGrammarTable.v2_8_2["RXA"]?.field(2)?.name == "Administration Sub-ID Counter")
        #expect(SegmentGrammarTable.v2_8_2["ITM"]?.field(33)?.name == "United Nations Standard Products and Services Code (UNSPSC)")
    }

    @Test("Repeatability follows each version's RP column: v2.3 PID-6 is single, v2.6 PID-38 repeats")
    func repeatabilityPerVersion() throws {
        #expect(SegmentGrammarTable.v2_3["PID"]?.field(6)?.repeatability == .single, "v2.3 prints no RP for Mother's Maiden Name")
        #expect(SegmentGrammarTable.v2_5_1["PID"]?.field(6)?.repeatability == .multiple)
        #expect(SegmentGrammarTable.v2_6["PID"]?.field(38)?.repeatability == .multiple, "v2.6 prints '2': a bounded repeat")
        #expect(SegmentGrammarTable.v2_8_2["OBX"]?.field(28)?.repeatability == .multiple)
        #expect(SegmentGrammarTable.v2_6["ERR"]?.field(9)?.repeatability == .multiple, "Y printed under the TBL# header")
        // v2.3 rejects a second mother's-maiden-name repetition; v2.5.1 allows it.
        func cardinality(_ version: String) throws -> Bool {
            let wire = "MSH|^~\\&|HIS|FAC|HOSPITAL|FAC|20240101120000||ADT^A01^ADT_A01|MSG00001|P|\(version)\rPID|1||123^^^HOSP^MR||DOE^JOHN|SMITH^MARY~JONES^ANN\r"
            return Validator().validate(try Parser().parse(wire)).issues.contains { $0.code == .cardinalityExceeded && $0.location.fieldIndex == 6 }
        }
        #expect(try cardinality("2.3"))
        #expect(try !cardinality("2.5.1"))
    }

    @Test("OBR optionality follows the printed tables (V231-C13, V24-C04, V26-C05)")
    func obrPrintedOptionality() {
        let tables: [(String, [String: SegmentGrammar])] = [
            ("2.3", SegmentGrammarTable.v2_3), ("2.3.1", SegmentGrammarTable.v2_3_1), ("2.4", SegmentGrammarTable.v2_4),
            ("2.5.1", SegmentGrammarTable.v2_5_1), ("2.6", SegmentGrammarTable.v2_6),
        ]
        for (version, table) in tables {
            for index in [8, 9, 10, 11, 20, 21, 26] {
                #expect(table["OBR"]?.field(index)?.optionality == .optional, "v\(version) OBR-\(index) is printed O")
            }
            // Printed O, modelled C from the child-order prose (§4.5.1.29 / §4.5.3.29; ORC §4.3.1.8 / §4.5.1.8).
            #expect(table["OBR"]?.field(29)?.optionality == .conditional, "v\(version) OBR-29")
            #expect(table["ORC"]?.field(8)?.optionality == .conditional, "v\(version) ORC-8")
        }
        // OBR-1: printed C in v2.3 (CH4 and CH7), O from v2.3.1.
        #expect(SegmentGrammarTable.v2_3["OBR"]?.field(1)?.optionality == .conditional)
        for (version, table) in tables.dropFirst() {
            #expect(table["OBR"]?.field(1)?.optionality == .optional, "v\(version) OBR-1")
        }
        // OBR-32: O through v2.5.1, B in v2.6.
        for (version, table) in tables.dropLast() {
            #expect(table["OBR"]?.field(32)?.optionality == .optional, "v\(version) OBR-32")
        }
        #expect(SegmentGrammarTable.v2_6["OBR"]?.field(32)?.optionality == .backwardCompat)
        // OBR-48: v2.6 CH04 sec 4.5.3.48 prints C (bare, no condition text given).
        #expect(SegmentGrammarTable.v2_6["OBR"]?.field(48)?.optionality == .conditional, "v2.6 OBR-48")
    }

    @Test("A populated OBR-32 warns as deprecated on v2.6 only")
    func obr32DeprecatedOnV26() throws {
        func warned(_ version: String) throws -> Bool {
            let obr = "OBR|1|ORD001|FIL001|GLUC^Glucose^L|||20240401080000"
                + String(repeating: "|", count: 18) + "F"
                + String(repeating: "|", count: 7) + "1234&Smith&John"
            let wire = "MSH|^~\\&|LAB|FAC|HIS|FAC|20240401090000||ORU^R01^ORU_R01|MSG00001|P|\(version)\rPID|1||123^^^AUTH^MR||DOE^JOHN\r\(obr)\r"
            let message = try Parser().parse(wire)
            #expect(message["OBR-25"] == "F", "Wire mis-counted")
            #expect(message["OBR-32.1.1"] == "1234", "Wire mis-counted")
            return try issues(wire).contains { $0.code == .fieldNotSupported && $0.location.pathDescription == "OBR[1]-32" }
        }
        #expect(try warned("2.6"), "v2.6 prints OBR-32 as B")
        #expect(try !warned("2.5.1"), "v2.5.1 prints OBR-32 as O")
    }
}
